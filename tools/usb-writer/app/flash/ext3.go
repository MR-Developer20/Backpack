package flash

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"sort"
	"time"
)

// A small, self-contained ext3 formatter (ext2 layout + an internal journal), so the writer can
// create the persistence partition on Windows and macOS, which have no mkfs.ext4. It writes only
// metadata: superblock (+ sparse backups), group descriptors, bitmaps, zeroed inode tables, the
// root directory, lost+found, the journal and a few small files in the root directory.
// Tests check the result with `e2fsck -fn`.

const (
	blockSize      = 4096
	blocksPerGroup = blockSize * 8
	inodeSize      = 256
	bytesPerInode  = 64 * 1024
	firstIno       = 11
	journalIno     = 8
	rootIno        = 2
	lostFoundIno   = 11
)

type fsLayout struct {
	blocks, groups, inodesPerGroup, itBlocks, gdtBlocks uint32
}

func hasSuper(g uint32) bool {
	if g <= 1 {
		return true
	}
	for _, b := range []uint32{3, 5, 7} {
		n := b
		for n < g {
			n *= b
		}
		if n == g {
			return true
		}
	}
	return false
}

func (l fsLayout) groupStart(g uint32) uint32 { return g * blocksPerGroup }
func (l fsLayout) groupBlocks(g uint32) uint32 {
	if g == l.groups-1 {
		return l.blocks - g*blocksPerGroup
	}
	return blocksPerGroup
}

// overhead: blocks used by sb/gdt backup, two bitmaps and the inode table at the start of group g.
func (l fsLayout) overhead(g uint32) uint32 {
	o := 2 + l.itBlocks
	if hasSuper(g) {
		o += 1 + l.gdtBlocks
	}
	return o
}
func (l fsLayout) blockBitmap(g uint32) uint32 {
	return l.groupStart(g) + l.overhead(g) - 2 - l.itBlocks
}
func (l fsLayout) inodeBitmap(g uint32) uint32 { return l.blockBitmap(g) + 1 }
func (l fsLayout) inodeTable(g uint32) uint32  { return l.blockBitmap(g) + 2 }

func layout(sizeBytes int64) (fsLayout, error) {
	var l fsLayout
	blocks := uint64(sizeBytes / blockSize)
	if blocks < 8192 { // 32 MiB
		return l, errors.New("persistence partition too small (minimum 32 MiB)")
	}
	if blocks > 1<<32-1 {
		return l, errors.New("persistence partition too large")
	}
	l.blocks = uint32(blocks)
	for {
		l.groups = (l.blocks + blocksPerGroup - 1) / blocksPerGroup
		inodes := uint64(l.blocks) * blockSize / bytesPerInode
		ipg := uint32((inodes + uint64(l.groups) - 1) / uint64(l.groups))
		perBlock := uint32(blockSize / inodeSize)
		ipg = (ipg + perBlock - 1) / perBlock * perBlock
		if ipg < perBlock {
			ipg = perBlock
		}
		if ipg > blocksPerGroup {
			ipg = blocksPerGroup
		}
		l.inodesPerGroup = ipg
		l.itBlocks = ipg / perBlock
		l.gdtBlocks = (l.groups*32 + blockSize - 1) / blockSize
		last := l.groups - 1
		if l.groups > 1 && l.groupBlocks(last) < l.overhead(last)+64 {
			l.blocks = last * blocksPerGroup // drop a stub last group, as mke2fs does
			continue
		}
		return l, nil
	}
}

func journalBlocks(blocks uint32) uint32 {
	switch {
	case blocks < 256*1024:
		return 4096
	case blocks < 512*1024:
		return 8192
	case blocks < 4096*1024:
		return 16384
	}
	return 32768
}

// allocator hands out free data blocks in order, skipping group metadata.
type allocator struct {
	l    fsLayout
	used map[uint32][]bool // per group, data block in-use flags
	g, i uint32
}

func (a *allocator) next() (uint32, error) {
	for a.g < a.l.groups {
		gb := a.l.groupBlocks(a.g)
		if a.i < a.l.overhead(a.g) {
			a.i = a.l.overhead(a.g)
		}
		if a.i < gb {
			b := a.l.groupStart(a.g) + a.i
			if a.used[a.g] == nil {
				a.used[a.g] = make([]bool, gb)
			}
			a.used[a.g][a.i] = true
			a.i++
			return b, nil
		}
		a.g, a.i = a.g+1, 0
	}
	return 0, errors.New("filesystem full")
}

type inode struct {
	mode       uint16
	links      uint16
	size       uint64
	block      [15]uint32
	dataBlocks uint32 // blocks counted in i_blocks (data + indirect)
}

func (in *inode) bytes(now uint32) []byte {
	b := make([]byte, inodeSize)
	le := binary.LittleEndian
	le.PutUint16(b[0:], in.mode)
	le.PutUint32(b[4:], uint32(in.size))
	le.PutUint32(b[8:], now)
	le.PutUint32(b[12:], now)
	le.PutUint32(b[16:], now)
	le.PutUint16(b[26:], in.links)
	le.PutUint32(b[28:], in.dataBlocks*(blockSize/512))
	for i, v := range in.block {
		le.PutUint32(b[40+4*i:], v)
	}
	le.PutUint32(b[108:], uint32(in.size>>32))
	le.PutUint16(b[128:], 32) // i_extra_isize
	return b
}

// mapBlocks fills in.block with direct/indirect pointers to data; it allocates indirect
// blocks and returns their contents keyed by block number.
func mapBlocks(a *allocator, in *inode, data []uint32) (map[uint32][]byte, error) {
	const per = blockSize / 4
	ind := map[uint32][]byte{}
	le := binary.LittleEndian
	n := copy(in.block[:12], data)
	rest := data[n:]
	in.dataBlocks = uint32(len(data))
	newInd := func() (uint32, []byte, error) {
		b, err := a.next()
		if err != nil {
			return 0, nil, err
		}
		buf := make([]byte, blockSize)
		ind[b] = buf
		in.dataBlocks++
		return b, buf, nil
	}
	if len(rest) > 0 {
		b, buf, err := newInd()
		if err != nil {
			return nil, err
		}
		in.block[12] = b
		k := min(per, len(rest))
		for i := 0; i < k; i++ {
			le.PutUint32(buf[4*i:], rest[i])
		}
		rest = rest[k:]
	}
	if len(rest) > 0 {
		b, dbuf, err := newInd()
		if err != nil {
			return nil, err
		}
		in.block[13] = b
		for j := 0; len(rest) > 0; j++ {
			if j == per {
				return nil, errors.New("journal too large")
			}
			ib, buf, err := newInd()
			if err != nil {
				return nil, err
			}
			le.PutUint32(dbuf[4*j:], ib)
			k := min(per, len(rest))
			for i := 0; i < k; i++ {
				le.PutUint32(buf[4*i:], rest[i])
			}
			rest = rest[k:]
		}
	}
	return ind, nil
}

type dirent struct {
	ino   uint32
	name  string
	ftype byte
}

func dirBlock(ents []dirent) []byte {
	b := make([]byte, blockSize)
	le := binary.LittleEndian
	off := 0
	for i, e := range ents {
		rec := (8 + len(e.name) + 3) &^ 3
		if i == len(ents)-1 {
			rec = blockSize - off
		}
		le.PutUint32(b[off:], e.ino)
		le.PutUint16(b[off+4:], uint16(rec))
		b[off+6] = byte(len(e.name))
		b[off+7] = e.ftype
		copy(b[off+8:], e.name)
		off += rec
	}
	return b
}

func emptyDirBlock() []byte {
	b := make([]byte, blockSize)
	binary.LittleEndian.PutUint16(b[4:], blockSize)
	return b
}

// FormatExt3 creates an ext3 filesystem of sizeBytes at byte offset off of w, labelled label,
// with files (name -> content, each at most one block) in its root directory.
// progress, if non-nil, is called with bytes of metadata written so far and the total.
func FormatExt3(w io.WriterAt, off, sizeBytes int64, label string, files map[string][]byte, progress func(done, total int64)) error {
	l, err := layout(sizeBytes)
	if err != nil {
		return err
	}
	if len(label) > 16 {
		return errors.New("label longer than 16 bytes")
	}
	names := make([]string, 0, len(files))
	for n, c := range files {
		if len(c) > blockSize || len(n) > 255 {
			return fmt.Errorf("file %s too large", n)
		}
		names = append(names, n)
	}
	sort.Strings(names)
	if firstIno+1+len(names) > int(l.inodesPerGroup) {
		return errors.New("too many files")
	}
	now := uint32(time.Now().Unix())
	le := binary.LittleEndian
	writeBlock := func(blk uint32, b []byte) error {
		_, err := w.WriteAt(b, off+int64(blk)*blockSize)
		return err
	}

	// Wipe the first and last MiB (old filesystem signatures, e.g. ISO9660 at 32 KiB, would make
	// blkid report an ambivalent result), then zero every inode table.
	zero := make([]byte, 1<<20)
	var total, done int64
	total = 2*int64(len(zero)) + int64(l.groups)*int64(l.itBlocks)*blockSize
	report := func(n int64) {
		done += n
		if progress != nil {
			progress(done, total)
		}
	}
	end := int64(l.blocks) * blockSize
	for _, at := range []int64{0, end - int64(len(zero))} {
		if _, err := w.WriteAt(zero, off+at); err != nil {
			return err
		}
		report(int64(len(zero)))
	}
	for g := uint32(0); g < l.groups; g++ {
		for left, blk := l.itBlocks, l.inodeTable(g); left > 0; {
			n := min(left, uint32(len(zero)/blockSize))
			if _, err := w.WriteAt(zero[:n*blockSize], off+int64(blk)*blockSize); err != nil {
				return err
			}
			report(int64(n) * blockSize)
			left -= n
			blk += n
		}
	}

	// data blocks
	a := &allocator{l: l, used: map[uint32][]bool{}}
	inodes := map[uint32]*inode{}
	rootBlk, err := a.next()
	if err != nil {
		return err
	}
	var lfBlks []uint32
	for i := 0; i < 4; i++ {
		b, err := a.next()
		if err != nil {
			return err
		}
		lfBlks = append(lfBlks, b)
	}
	rootEnts := []dirent{{rootIno, ".", 2}, {rootIno, "..", 2}, {lostFoundIno, "lost+found", 2}}
	blocks := map[uint32][]byte{}
	for i, n := range names {
		ino := uint32(firstIno + 1 + i)
		b, err := a.next()
		if err != nil {
			return err
		}
		buf := make([]byte, blockSize)
		copy(buf, files[n])
		blocks[b] = buf
		in := &inode{mode: 0o100644, links: 1, size: uint64(len(files[n]))}
		in.block[0] = b
		in.dataBlocks = 1
		inodes[ino] = in
		rootEnts = append(rootEnts, dirent{ino, n, 1})
	}
	blocks[rootBlk] = dirBlock(rootEnts)
	root := &inode{mode: 0o40755, links: 3, size: blockSize, dataBlocks: 1}
	root.block[0] = rootBlk
	inodes[rootIno] = root
	lf := &inode{mode: 0o40700, links: 2, size: uint64(len(lfBlks)) * blockSize}
	copy(lf.block[:], lfBlks)
	lf.dataBlocks = uint32(len(lfBlks))
	inodes[lostFoundIno] = lf
	blocks[lfBlks[0]] = dirBlock([]dirent{{lostFoundIno, ".", 2}, {rootIno, "..", 2}})
	for _, b := range lfBlks[1:] {
		blocks[b] = emptyDirBlock()
	}

	// journal
	jn := journalBlocks(l.blocks)
	jdata := make([]uint32, jn)
	// allocate the journal after its first indirect blocks would be; simplest is data first
	for i := range jdata {
		if jdata[i], err = a.next(); err != nil {
			return err
		}
	}
	jin := &inode{mode: 0o100600, links: 1, size: uint64(jn) * blockSize}
	ind, err := mapBlocks(a, jin, jdata)
	if err != nil {
		return err
	}
	for b, buf := range ind {
		blocks[b] = buf
	}
	inodes[journalIno] = jin
	uuid := make([]byte, 16)
	if _, err := rand.Read(uuid); err != nil {
		return err
	}
	uuid[6] = uuid[6]&0x0f | 0x40
	uuid[8] = uuid[8]&0x3f | 0x80
	jsb := make([]byte, blockSize)
	be := binary.BigEndian
	be.PutUint32(jsb[0:], 0xC03B3998) // magic
	be.PutUint32(jsb[4:], 4)          // superblock v2
	be.PutUint32(jsb[12:], blockSize)
	be.PutUint32(jsb[16:], jn)
	be.PutUint32(jsb[20:], 1) // s_first
	be.PutUint32(jsb[24:], 1) // s_sequence
	copy(jsb[48:], uuid)
	be.PutUint32(jsb[64:], 1) // s_nr_users
	blocks[jdata[0]] = jsb

	// per-group accounting
	usedDirs := map[uint32]uint16{0: 2}
	var freeBlocks, freeInodes uint64
	gdt := make([]byte, l.gdtBlocks*blockSize)
	bitmaps := map[uint32][]byte{}
	for g := uint32(0); g < l.groups; g++ {
		gb := l.groupBlocks(g)
		bb := make([]byte, blockSize)
		var usedB uint32
		for i := uint32(0); i < blocksPerGroup; i++ {
			inUse := i >= gb || i < l.overhead(g) || (a.used[g] != nil && a.used[g][i])
			if inUse {
				bb[i/8] |= 1 << (i % 8)
				if i < gb {
					usedB++
				}
			}
		}
		ib := make([]byte, blockSize)
		var usedI uint32
		for i := uint32(0); i < blockSize*8; i++ {
			ino := g*l.inodesPerGroup + i + 1
			inUse := i >= l.inodesPerGroup || (g == 0 && (ino < firstIno || inodes[ino] != nil))
			if inUse {
				ib[i/8] |= 1 << (i % 8)
				if i < l.inodesPerGroup {
					usedI++
				}
			}
		}
		bitmaps[l.blockBitmap(g)] = bb
		bitmaps[l.inodeBitmap(g)] = ib
		fb, fi := gb-usedB, l.inodesPerGroup-usedI
		freeBlocks += uint64(fb)
		freeInodes += uint64(fi)
		d := gdt[g*32:]
		le.PutUint32(d[0:], l.blockBitmap(g))
		le.PutUint32(d[4:], l.inodeBitmap(g))
		le.PutUint32(d[8:], l.inodeTable(g))
		le.PutUint16(d[12:], uint16(fb))
		le.PutUint16(d[14:], uint16(fi))
		le.PutUint16(d[16:], usedDirs[g])
	}

	// superblock
	sb := make([]byte, 1024)
	le.PutUint32(sb[0:], l.groups*l.inodesPerGroup)
	le.PutUint32(sb[4:], l.blocks)
	le.PutUint32(sb[12:], uint32(freeBlocks))
	le.PutUint32(sb[16:], uint32(freeInodes))
	le.PutUint32(sb[24:], 2) // log block size: 4096
	le.PutUint32(sb[28:], 2)
	le.PutUint32(sb[32:], blocksPerGroup)
	le.PutUint32(sb[36:], blocksPerGroup)
	le.PutUint32(sb[40:], l.inodesPerGroup)
	le.PutUint32(sb[48:], now)
	le.PutUint16(sb[54:], 0xFFFF) // max mount count: -1
	le.PutUint16(sb[56:], 0xEF53)
	le.PutUint16(sb[58:], 1) // clean
	le.PutUint16(sb[60:], 1) // errors: continue
	le.PutUint32(sb[64:], now)
	le.PutUint32(sb[76:], 1) // dynamic rev
	le.PutUint32(sb[84:], firstIno)
	le.PutUint16(sb[88:], inodeSize)
	le.PutUint32(sb[92:], 0x4|0x8)  // compat: has_journal, ext_attr
	le.PutUint32(sb[96:], 0x2)      // incompat: filetype
	le.PutUint32(sb[100:], 0x1|0x2) // ro_compat: sparse_super, large_file
	copy(sb[104:], uuid)
	copy(sb[120:], label)
	le.PutUint32(sb[224:], journalIno)
	if _, err := rand.Read(sb[236:252]); err != nil { // hash seed
		return err
	}
	sb[252] = 1                     // half_md4
	sb[253] = 1                     // s_jnl_backup_type: journal inode blocks are backed up below
	le.PutUint32(sb[256:], 0x4|0x8) // default mount: user_xattr, acl
	le.PutUint32(sb[264:], now)
	for i, v := range jin.block {
		le.PutUint32(sb[268+4*i:], v)
	}
	le.PutUint32(sb[268+60:], uint32(jin.size>>32))
	le.PutUint32(sb[268+64:], uint32(jin.size))
	le.PutUint16(sb[348:], 32)  // min extra isize
	le.PutUint16(sb[350:], 32)  // want extra isize
	le.PutUint32(sb[352:], 0x2) // unsigned directory hash

	for g := uint32(0); g < l.groups; g++ {
		if !hasSuper(g) {
			continue
		}
		blk := make([]byte, blockSize)
		at := 0
		if g == 0 {
			at = 1024
		}
		copy(blk[at:], sb)
		le.PutUint16(blk[at+90:], uint16(g))
		if err := writeBlock(l.groupStart(g), blk); err != nil {
			return err
		}
		if _, err := w.WriteAt(gdt, off+int64(l.groupStart(g)+1)*blockSize); err != nil {
			return err
		}
	}
	for b, buf := range bitmaps {
		if err := writeBlock(b, buf); err != nil {
			return err
		}
	}
	// inode table entries (all used inodes live in group 0)
	perBlock := uint32(blockSize / inodeSize)
	itab := map[uint32][]byte{}
	for ino, in := range inodes {
		idx := ino - 1
		blk := l.inodeTable(0) + idx/perBlock
		if itab[blk] == nil {
			itab[blk] = make([]byte, blockSize)
		}
		copy(itab[blk][(idx%perBlock)*inodeSize:], in.bytes(now))
	}
	for b, buf := range itab {
		if err := writeBlock(b, buf); err != nil {
			return err
		}
	}
	for b, buf := range blocks {
		if err := writeBlock(b, buf); err != nil {
			return err
		}
	}
	return nil
}
