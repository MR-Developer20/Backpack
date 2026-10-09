#!/bin/sh

#set -e

# NetToolkit: copy with progress reported to plymouth ("toram:<pct>" messages drawn as a bar by
# the nettoolkit theme) or, without plymouth, to the console.
nettoolkit_copy_progress ()
{
	dst="$1"; shift
	total=0
	for s in "$@"
	do
		k=$(du -sk "$s" 2>/dev/null | cut -f1)
		total=$((total + ${k:-0}))
	done
	[ "$total" -gt 0 ] || total=1
	( cp -a "$@" "${dst}/" ) &
	cppid=$!
	last=-1
	while kill -0 $cppid 2>/dev/null
	do
		done_k=$(du -sk "$dst" 2>/dev/null | cut -f1)
		pct=$(( ${done_k:-0} * 100 / total ))
		[ $pct -gt 100 ] && pct=100
		if [ $pct -ne $last ]
		then
			if plymouth --ping 2>/dev/null
			then
				plymouth message --text="toram:${pct}"
			else
				printf '\r * Copying to RAM: %3d%%' "$pct" 1>/dev/console
			fi
			last=$pct
		fi
		sleep 1
	done
	wait $cppid
	plymouth message --text="toram:100" 2>/dev/null || true
}

copy_live_to ()
{
	copyfrom="${1}"
	copytodev="${2}"
	copyto="${copyfrom}_swap"

	if [ -z "${MODULETORAM}" ]
	then
		size=$(fs_size "" ${copyfrom}/ "used")
	else
		MODULETORAMFILE="${copyfrom}/${LIVE_MEDIA_PATH}/${MODULETORAM}"

		if [ -f "${MODULETORAMFILE}" ]
		then
			size=$( expr $(ls -la ${MODULETORAMFILE} | awk '{print $5}') / 1024 + 5000 )
		else
			log_warning_msg "Error: toram-module ${MODULETORAM} (${MODULETORAMFILE}) could not be read."
			return 1
		fi
	fi

	if [ "${copytodev}" = "ram" ]
	then
		# copying to ram:
		freespace=$(awk '/^MemFree:/{f=$2} /^Cached:/{c=$2} END{print f+c}' /proc/meminfo)
		mount_options="-o size=${size}k"
		free_string="memory"
		fstype="tmpfs"
		dev="tmpfs"
	else
		# it should be a writable block device
		if [ -b "${copytodev}" ]
		then
			dev="${copytodev}"
			free_string="space"
			fstype=$(get_fstype "${dev}")
			freespace=$(fs_size "${dev}")
		else
			log_warning_msg "${copytodev} is not a block device."
			return 1
		fi
	fi

	if [ "${freespace}" -lt "${size}" ]
	then
		log_warning_msg "Not enough free ${free_string} (${freespace}k free, ${size}k needed) to copy live media in ${copytodev}."
		return 1
	fi

	# Custom ramdisk size
	if [ -z "${mount_options}" ] && [ -n "${ramdisk_size}" ]
	then
		# FIXME: should check for wrong values
		mount_options="-o size=${ramdisk_size}"
	fi

	# begin copying (or uncompressing)
	mkdir "${copyto}"
	log_begin_msg "mount -t ${fstype} ${mount_options} ${dev} ${copyto}"
	mount -t "${fstype}" ${mount_options} "${dev}" "${copyto}"

	if [ "${extension}" = "tgz" ]
	then
		cd "${copyto}"
		tar zxf "${copyfrom}/${LIVE_MEDIA_PATH}/$(basename ${FETCH})"
		rm -f "${copyfrom}/${LIVE_MEDIA_PATH}/$(basename ${FETCH})"
		mount -r -o move "${copyto}" "${rootmnt}"
		cd "${OLDPWD}"
	else
		if [ -n "${MODULETORAMFILE}" ]
		then
			nettoolkit_copy_progress "${copyto}" "${MODULETORAMFILE}"   # copy only the filesystem module
		else
			nettoolkit_copy_progress "${copyto}" ${copyfrom}/*
			if [ -e ${copyfrom}/${LIVE_MEDIA_PATH}/.disk ]
			then
				cp -a ${copyfrom}/${LIVE_MEDIA_PATH}/.disk ${copyto}
			fi
		fi

		umount ${copyfrom}
		mount -r -o move ${copyto} ${copyfrom}
	fi

	rmdir ${copyto}
	return 0
}
