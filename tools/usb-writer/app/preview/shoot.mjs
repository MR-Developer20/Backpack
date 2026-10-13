// Renders the window's frontend in Chromium with a fake Go side, for screenshots without a
// build or a USB drive:  NODE_PATH=$(npm root -g) node preview/shoot.mjs OUTDIR
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const { chromium } = createRequire(import.meta.url)("playwright"); // NODE_PATH: global install
const here = path.dirname(fileURLToPath(import.meta.url));
const dist = path.join(here, "..", "frontend", "dist", "index.html");
const out = process.argv[2] || ".";

const mock = (scenario) => {
  const GB = 1e9;
  const iso = { path: "/home/marc/Downloads/backpack-live-v1.0.0-amd64.iso", name: "backpack-live-v1.0.0-amd64.iso", size: 1072693248, volume: "BACKPACK_LIVE" };
  const drives = [
    { path: "/dev/sdb", display: "/dev/sdb", name: "SanDisk Ultra Fit", bus: "USB", size: 30.8 * GB, persistence: false, mounted: ["/dev/sdb1"] },
    { path: "/dev/sdc", display: "/dev/sdc", name: "Kingston DataTraveler 3.0", bus: "USB", size: 61.9 * GB, persistence: true, mounted: [] },
  ];
  const handlers = {};
  window.runtime = { EventsOn: (n, f) => (handlers[n] = f), OnFileDrop: () => {} };
  const s = scenario;
  window.go = { main: { App: {
    Info: async () => ({ os: "Linux", version: "v1.0.0", iso: s === "empty" ? null : iso, elevated: false }),
    Drives: async () => (s === "empty" ? [] : drives),
    PickISO: async () => iso,
    CheckUpdate: async () => ({ current: "v1.0.0", latest: "v1.1.0", page: "", newer: true, isoName: "backpack-live-v1.1.0-amd64.iso", isoSize: 1084227584 }),
    InstallUpdate: async () => { setTimeout(() => handlers.update({ kind: "app", ready: s === "update-ready", done: 4.1e6, total: 9.6e6 }), 30); },
    DownloadISO: async () => { setTimeout(() => handlers.update({ kind: "iso", done: 4.6e8, total: 1084227584 }), 30); },
    RestartApp: async () => {},
    Inspect: async () => iso,
    Command: async (r) => `backpack-usb-writer --iso ${r.iso.replace("/home/marc", "~")} ${r.keep ? "--keep-persistence" : `--size ${r.sizeGB}G`} ${r.device}`,
    Write: async () => {
      const emit = (e) => handlers.job(e);
      const t = s;
      setTimeout(() => {
        emit({ phase: "auth", log: "Asking for your password" });
        emit({ phase: "prepare", log: "Opening /dev/sdb" });
        emit({ log: "Unmounting /media/marc/BACKPACK_LIVE" });
        emit({ phase: "image", done: 0, total: iso.size, log: "Writing backpack-live-v1.0.0-amd64.iso (1.1 GB)" });
        if (t === "writing") { window.__t0(); emit({ phase: "image", done: iso.size * 0.62, total: iso.size }); return; }
        emit({ phase: "image", done: iso.size, total: iso.size });
        emit({ phase: "sync", log: "Flushing the image to the drive" });
        emit({ phase: "partition", log: "Adding partition 3: start sector 2097152, 8.6 GB" });
        emit({ phase: "format", log: "Creating the persistence filesystem (ext3, label persistence)" });
        if (t === "failed") { emit({ error: "write at 640.0 MB: input/output error", end: true }); return; }
        emit({ phase: "format", done: 1, total: 1 });
        emit({ phase: "sync", log: "Flushing to the drive" });
        emit({ log: "Re-reading the partition table" });
        emit({ phase: "done", log: "Done. You can remove the drive.", end: true });
      }, 50);
    },
  } } };
};

const pickDrive = async (p, n) => { await p.click("#drive-dd .dd-btn"); await p.click(`#drive-dd .dd-opt:nth-child(${n})`); };
const plus = async (p, k) => { for (let i = 0; i < k; i++) await p.click("#size-inc"); };
const W = 560, H = 780;
const shots = [
  ["empty", W, H, async () => {}],
  ["ready", W, H, async (p) => { await pickDrive(p, 1); await plus(p, 3); }],
  ["drive-list", W, H, async (p) => { await pickDrive(p, 1); await p.click("#drive-dd .dd-btn"); }],
  ["mode-list", W, H, async (p) => { await pickDrive(p, 2); await p.click("#mode-dd .dd-btn"); }],
  ["keep", W, H, async (p) => { await pickDrive(p, 2); }],
  ["confirm", W, H, async (p) => { await pickDrive(p, 1); await plus(p, 3); await p.click("#write"); }],
  ["writing", W, H, async (p) => { await pickDrive(p, 1); await plus(p, 3); await p.click("#write"); await p.click("#c-ok"); await p.waitForTimeout(300); }],
  ["done", W, H, async (p) => { await pickDrive(p, 1); await plus(p, 3); await p.click("#write"); await p.click("#c-ok"); await p.waitForTimeout(300); }],
  ["failed", W, H, async (p) => { await pickDrive(p, 1); await p.click("#write"); await p.click("#c-ok"); await p.waitForTimeout(300); }],
  ["update", W, H, async (p) => { await pickDrive(p, 1); await p.click("#upd"); await p.click("#iso-dl"); await p.waitForTimeout(200); }],
  ["update-ready", W, H, async (p) => { await pickDrive(p, 1); await p.click("#upd"); await p.waitForTimeout(200); }],
  ["min", 480, 660, async (p) => { await pickDrive(p, 1); }],
];

const browser = await chromium.launch();
for (const [name, w, h, act] of shots) {
  const page = await browser.newPage({ viewport: { width: w, height: h } });
  const scenario = ["min", "drive-list", "mode-list"].includes(name) ? "ready" : name;
  await page.addInitScript(mock, scenario);
  await page.addInitScript(() => { window.__t0 = () => {}; });
  await page.goto("file://" + dist);
  await page.waitForTimeout(300);
  await act(page);
  if (name === "writing") await page.evaluate(() => { document.getElementById("rate").textContent = "62% // 665.1 MB OF 1.1 GB // 24.3 MB/S"; });
  await page.screenshot({ path: path.join(out, `writer-${name}.png`) });
  await page.close();
}
await browser.close();
