"use strict";
// Backpack USB Writer window. Talks to the Go side through Wails: window.go.main.App.* calls and
// "job" events (see app.go).

const $ = (id) => document.getElementById(id);
const api = () => window.go.main.App;
const GiB = 1024 ** 3;

const state = { rel: null, info: null, iso: null, drives: [], sel: null, keep: false, size: 5, running: false, finished: false, phases: {}, t0: 0 };

function human(n) {
  let f = n;
  for (const u of ["B", "KB", "MB", "GB"]) {
    if (f < 1000) return u === "B" ? `${n} B` : `${f.toFixed(1)} ${u}`;
    f /= 1000;
  }
  return `${f.toFixed(1)} TB`;
}

function drive() { return state.drives.find((d) => d.path === state.sel) || null; }

function maxSize() {
  const d = drive();
  if (!d) return 64;
  const free = d.size - (state.iso ? state.iso.size : 0) - 16 * 1024 * 1024;
  return Math.max(1, Math.min(256, Math.floor(free / GiB)));
}

// ---------------------------------------------------------------- dropdown (styled listbox)
// items: [{value, main, sub, tag, disabled}]; empty: text shown when there are no items.
function dropdown(el, cls, onPick) {
  el.classList.add(cls);
  el.innerHTML = `<button class="dd-btn cut" aria-haspopup="listbox" aria-expanded="false"><div class="rail"></div>
    <div class="txt"><span class="main"></span><span class="sub"></span></div><span class="micro tag"></span><span class="caret"></span></button>
    <div class="dd-list cut" role="listbox"></div>`;
  const btn = el.querySelector(".dd-btn"), list = el.querySelector(".dd-list");
  const dd = { items: [], value: null, hl: -1 };
  const close = () => { el.classList.remove("open"); btn.setAttribute("aria-expanded", "false"); };
  const open = () => {
    if (!dd.items.length) return;
    document.querySelectorAll(".dd.open").forEach((o) => o !== el && o.classList.remove("open"));
    el.classList.add("open"); btn.setAttribute("aria-expanded", "true");
    dd.hl = Math.max(0, dd.items.findIndex((i) => i.value === dd.value));
    paintList();
  };
  const pick = (it) => { if (!it || it.disabled) return; close(); onPick(it.value); btn.focus(); };
  function paintList() {
    list.innerHTML = "";
    dd.items.forEach((it, i) => {
      const o = document.createElement("button");
      o.className = "dd-opt" + (i === dd.hl ? " hl" : "");
      o.setAttribute("role", "option");
      o.setAttribute("aria-selected", String(it.value === dd.value));
      o.disabled = !!it.disabled;
      o.innerHTML = `<div class="rail"></div><div class="txt"><span class="main"></span><span class="sub"></span></div><span class="micro tag"></span>`;
      o.querySelector(".main").textContent = it.main;
      o.querySelector(".sub").textContent = it.sub || "";
      o.querySelector(".tag").textContent = it.tag || "";
      o.onclick = () => pick(it);
      list.append(o);
    });
  }
  btn.onclick = () => (el.classList.contains("open") ? close() : open());
  btn.onkeydown = (e) => {
    if (!el.classList.contains("open")) {
      if (["ArrowDown", "ArrowUp", "Enter", " "].includes(e.key)) { e.preventDefault(); open(); }
      return;
    }
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); close(); }
    else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const n = dd.items.length, d = e.key === "ArrowDown" ? 1 : -1;
      for (let k = 1; k <= n; k++) { const j = (dd.hl + d * k + n) % n; if (!dd.items[j].disabled) { dd.hl = j; break; } }
      paintList();
    } else if (e.key === "Enter" || e.key === " ") { e.preventDefault(); pick(dd.items[dd.hl]); }
  };
  document.addEventListener("mousedown", (e) => { if (!el.contains(e.target)) close(); });
  dd.set = (items, value, empty, disabled) => {
    dd.items = items; dd.value = value;
    const cur = items.find((i) => i.value === value);
    btn.querySelector(".main").textContent = cur ? cur.main : empty;
    btn.querySelector(".sub").textContent = cur ? cur.sub || "" : "";
    btn.querySelector(".sub").hidden = !cur || !cur.sub;
    btn.querySelector(".tag").textContent = cur ? cur.tag || "" : "";
    btn.disabled = disabled || !items.length;
    if (btn.disabled) close();
    if (el.classList.contains("open")) paintList();
  };
  return dd;
}

let driveDD, modeDD;

// ---------------------------------------------------------------- render
function renderISO() {
  const t = $("iso-tile"), iso = state.iso;
  t.classList.toggle("empty", !iso);
  if (!iso) {
    $("iso-name").textContent = "No image chosen";
    $("iso-facts").textContent = "CHOOSE AN ISO OR DROP ONE HERE";
    $("iso-meta").textContent = "";
    return;
  }
  $("iso-name").textContent = iso.name;
  $("iso-tile").title = iso.path;
  if (iso.error) {
    $("iso-facts").innerHTML = "";
    const s = document.createElement("span");
    s.className = "err"; s.textContent = "NOT USABLE: " + iso.error.toUpperCase();
    $("iso-facts").append(s);
  } else {
    $("iso-facts").textContent = `${iso.volume || "NO LABEL"} // ${human(iso.size)}`;
  }
  $("iso-meta").textContent = iso.error ? "INVALID" : "ISO 9660";
}

function renderDrives() {
  $("drive-meta").textContent = `${state.drives.length} FOUND`;
  const items = state.drives.map((d) => ({
    value: d.path, main: d.name, sub: `${d.display} · ${human(d.size)} · ${d.bus || "USB"}`,
    tag: d.persistence ? "PERSISTENCE" : d.mounted && d.mounted.length ? "MOUNTED" : "",
  }));
  driveDD.set(items, state.sel, state.drives.length ? "Choose a USB drive" : "No USB drive found", state.running);
}

function renderMode() {
  const d = drive();
  const canKeep = !!(d && d.persistence);
  if (!canKeep) state.keep = false;
  modeDD.set([
    { value: "fresh", main: "Fresh install", sub: "Erase the drive, new persistence" },
    { value: "keep", main: "Update system", sub: canKeep ? "Keep saved files and settings" : "Needs a drive with persistence", disabled: !canKeep },
  ], state.keep ? "keep" : "fresh", "", state.running);
  const max = maxSize();
  state.size = Math.min(state.size, max);
  $("size").max = max;
  $("size").value = state.size;
  $("size-val").textContent = `${state.size} GB`;
  $("size-max").textContent = d && !state.keep ? `PERSISTENCE MAX ${max} GB` : "";
  $("size-block").classList.toggle("disabled-block", state.keep || state.running);
  $("size-block").hidden = state.keep;
}

function request() {
  return { iso: state.iso ? state.iso.path : "", device: state.sel || "", sizeGB: state.size, keep: state.keep };
}

let cmdSeq = 0;
async function renderCommand() {
  const ready = state.iso && !state.iso.error && drive();
  const ph = $("cmdline");
  if (!ready) {
    const parts = [state.iso && !state.iso.error ? "--iso " + state.iso.name : "--iso <image>",
      state.keep ? "--keep-persistence" : `--size ${state.size}G`, drive() ? drive().path : "<drive>"];
    ph.textContent = "backpack-usb-writer " + parts.join(" ");
    return;
  }
  const seq = ++cmdSeq;
  const cmd = await api().Command(request());
  if (seq === cmdSeq) { ph.textContent = cmd; ph.title = cmd; }
}

function renderWrite() {
  const d = drive();
  const ok = state.iso && !state.iso.error && d && !state.running;
  $("write").disabled = !ok;
  $("write-lbl").textContent = state.running ? "Writing…" : state.finished ? "Write again" : state.keep ? "Update" : "Write";
  if (!state.running && !state.finished) {
    let s = "";
    if (!state.iso) s = "Choose an image and a drive.";
    else if (state.iso.error) s = state.rel && state.rel.isoName
      ? `That file is not the Backpack ISO. Download ${state.rel.latest} above, or choose ${state.rel.isoName}.`
      : "That file is not the Backpack ISO. Choose backpack-live-<version>-amd64.iso from the release page.";
    else if (!d) s = state.drives.length ? "Choose the USB drive to write." : "Plug in a USB drive.";
    else if (state.keep) s = "Ready. The system is replaced, persistence is kept.";
    else s = `Ready. Everything on ${d.display} will be erased.`;
    setStatus(s, state.iso && d && !state.iso.error ? (state.keep ? "" : "warn") : "");
  }
}

function render() { renderISO(); renderDrives(); renderMode(); renderWrite(); renderCommand(); }

function setStatus(text, cls) {
  const s = $("status");
  s.textContent = text;
  s.className = "status small" + (cls ? " " + cls : "");
}

// ---------------------------------------------------------------- output pane
function log(text, err) {
  const pre = $("log");
  const line = document.createElement("span");
  if (err) line.className = "e";
  line.textContent = text + "\n";
  pre.append(line);
  pre.scrollTop = pre.scrollHeight;
  $("out").classList.remove("empty");
  $("dragon").style.display = "none";
  $("empty-note").style.display = "none";
}

function resetJob() {
  $("log").textContent = "";
  state.phases = {};
  for (const p of document.querySelectorAll(".phase")) p.className = "phase micro";
  $("meter").className = "meter";
  $("meter").firstElementChild.style.width = "0";
  $("rate").textContent = "";
}

const order = ["image", "partition", "format", "sync"];
function setPhase(p) {
  if (!order.includes(p)) return;
  const i = order.indexOf(p);
  for (const el of document.querySelectorAll(".phase")) {
    const j = order.indexOf(el.dataset.p);
    el.className = "phase micro" + (j < i ? " done" : j === i ? " active" : "");
  }
}

function onJob(e) {
  if (e.log) log(e.log, false);
  if (e.phase === "auth") setStatus("Waiting for your password…", "warn");
  if (e.phase === "prepare") setStatus("Preparing the drive…", "warn");
  if (e.phase && order.includes(e.phase)) {
    setPhase(e.phase === "sync" && state.phases.format ? "sync" : e.phase);
    state.phases[e.phase] = true;
  }
  if (e.total > 0) {
    const pct = Math.min(100, (e.done / e.total) * 100);
    $("meter").firstElementChild.style.width = pct + "%";
    if (e.phase === "image") {
      if (!state.t0) state.t0 = performance.now();
      const secs = (performance.now() - state.t0) / 1000;
      const rate = secs > 0.5 ? ` // ${human(e.done / secs)}/S` : "";
      $("rate").textContent = `${pct.toFixed(0)}% // ${human(e.done)} OF ${human(e.total)}${rate}`;
      setStatus("Writing the image. Do not unplug the drive.", "warn");
    } else if (e.phase === "format") {
      $("rate").textContent = `${pct.toFixed(0)}%`;
      setStatus("Creating the persistence partition…", "warn");
    }
  }
  if (e.error) {
    log("error: " + e.error, true);
    $("rate").textContent = "";
    setStatus("Failed: " + e.error, "err");
    $("meter").classList.add("failed");
    const act = document.querySelector(".phase.active");
    if (act) act.className = "phase micro failed";
  }
  if (e.end) {
    state.running = false;
    state.t0 = 0;
    if (!e.error) {
      state.finished = true;
      for (const el of document.querySelectorAll(".phase")) el.className = "phase micro done";
      $("meter").firstElementChild.style.width = "100%";
      $("rate").textContent = "DONE";
      setStatus("Finished. You can remove the drive.", "ok");
    }
    refreshDrives(true);
  }
}

// ---------------------------------------------------------------- actions
async function refreshDrives(keepStatus) {
  try {
    state.drives = (await api().Drives()) || [];
  } catch (err) {
    state.drives = [];
    log("error: " + err, true);
  }
  if (!drive()) state.sel = state.drives.length === 1 ? state.drives[0].path : null;
  const d = drive();
  if (d && !state.running && !keepStatus) state.keep = !!d.persistence;
  const status = $("status").textContent, cls = $("status").className;
  render();
  if (keepStatus) { $("status").textContent = status; $("status").className = cls; }
}

async function setISO(info) {
  if (!info) return;
  state.iso = info;
  state.finished = false;
  render();
}

function openConfirm() {
  const d = drive(), iso = state.iso;
  $("c-drive").textContent = `${d.display} · ${d.name} · ${human(d.size)}`;
  $("c-iso").textContent = `${iso.name} (${human(iso.size)})`;
  if (state.keep) {
    $("c-head").textContent = "Replaces the system";
    $("c-head").className = "label warnhead keep";
    $("c-title").textContent = "Update the system?";
    $("c-body").textContent = "The system on this drive is replaced with the new image. The persistence partition, with your files, Wi-Fi and settings, is kept.";
    $("c-persist").textContent = "Kept as it is";
    $("c-ok").className = "btn primary cut";
    $("c-ok-lbl").textContent = "Update";
  } else {
    $("c-head").textContent = "Erases the drive";
    $("c-head").className = "label warnhead";
    $("c-title").textContent = `Erase ${d.display}?`;
    $("c-body").textContent = "Everything on this drive is erased and replaced with the image and a new, empty persistence partition.";
    $("c-persist").textContent = `${state.size} GB, new and empty`;
    $("c-ok").className = "btn danger cut";
    $("c-ok-lbl").textContent = "Erase and write";
  }
  $("c-ok-cmd").textContent = $("cmdline").textContent;
  $("confirm").hidden = false;
  $("c-cancel").focus();
}

async function start() {
  $("confirm").hidden = true;
  resetJob();
  state.running = true;
  state.finished = false;
  render();
  log("$ " + $("cmdline").textContent);
  try {
    await api().Write(request());
  } catch (err) {
    onJob({ error: String(err), end: true });
  }
}

function step(n) {
  state.size = Math.max(1, Math.min(maxSize(), state.size + n));
  render();
}

// ---------------------------------------------------------------- updates from GitHub releases
async function checkUpdate() {
  let u;
  try { u = await api().CheckUpdate(); } catch (_) { return; } // offline: say nothing
  state.rel = u;
  if (u.newer) {
    $("upd").hidden = false;
    $("upd-lbl").textContent = `Update to ${u.latest}`;
  }
  if (u.isoName) {
    $("release").hidden = false;
    $("iso-dl-lbl").textContent = `Download ${u.latest}`;
    $("rel-facts").textContent = `LATEST RELEASE // ${u.latest} // ${human(u.isoSize)}`;
  }
  // the + extras edition (the Extra tab's apps), on releases that have one
  if (u.isoName && u.extrasName) {
    $("iso-dl-x").hidden = false;
    $("iso-dl-x-lbl").textContent = "Download + Extras";
    $("rel-facts").textContent = `LATEST RELEASE // ${u.latest} // ${human(u.isoSize)} // + EXTRAS ${human(u.extrasSize)}`;
  }
}

function onUpdate(e) {
  if (e.kind === "app") {
    const b = $("upd");
    b.className = "btn cut upd";
    if (e.error) {
      b.classList.add("failed");
      $("upd-lbl").textContent = "Update failed";
      b.disabled = false;
      log("update: " + e.error, true);
    } else if (e.ready) {
      b.classList.add("ready");
      $("upd-lbl").textContent = "Restart to finish";
      $("upd-cmd").textContent = `${state.rel.latest} installed`;
      b.disabled = false;
      b.onclick = () => api().RestartApp();
    } else {
      $("upd-lbl").textContent = `Updating ${e.total ? Math.floor((e.done / e.total) * 100) : 0}%`;
    }
    return;
  }
  const m = $("dl-meter");
  if (e.error) {
    m.classList.add("failed");
    $("rel-facts").innerHTML = "";
    const s = document.createElement("span");
    s.className = "err-text"; s.textContent = "Download failed: " + e.error;
    $("rel-facts").append(s);
    $("iso-dl").disabled = $("iso-dl-x").disabled = false;
  } else if (e.ready) {
    m.firstElementChild.style.width = "100%";
    $("rel-facts").textContent = `SAVED TO DOWNLOADS // ${state.rel.latest}`;
    $("iso-dl").disabled = $("iso-dl-x").disabled = false;
    if (e.iso && !state.running) setISO(e.iso);
  } else if (e.total) {
    m.hidden = false;
    m.classList.remove("failed");
    const pct = (e.done / e.total) * 100;
    m.firstElementChild.style.width = pct + "%";
    $("rel-facts").textContent = `DOWNLOADING // ${pct.toFixed(0)}% // ${human(e.done)} OF ${human(e.total)}`;
  }
}

// ---------------------------------------------------------------- empty state: dragon curve
function drawDragon() {
  const c = $("dragon"), r = c.getBoundingClientRect();
  if (!r.width) return;
  const dpr = window.devicePixelRatio || 1;
  c.width = r.width * dpr; c.height = r.height * dpr;
  const g = c.getContext("2d");
  g.scale(dpr, dpr);
  // turn sequence for iteration n
  const n = 9;
  let turns = [];
  for (let i = 0; i < n; i++) turns = [...turns, 1, ...turns.slice().reverse().map((t) => -t)];
  let x = 0, y = 0, dir = 0;
  const pts = [[0, 0]];
  const dx = [1, 0, -1, 0], dy = [0, 1, 0, -1];
  for (const t of [0, ...turns]) {
    dir = (dir + t + 4) % 4;
    x += dx[dir]; y += dy[dir];
    pts.push([x, y]);
  }
  const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
  const [minX, maxX, minY, maxY] = [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)];
  const s = Math.min((r.width * 0.5) / (maxX - minX), (r.height - 40) * 0.8 / (maxY - minY));
  const ox = (r.width - (maxX - minX) * s) / 2 - minX * s, oy = (r.height - 16 - (maxY - minY) * s) / 2 - minY * s;
  g.strokeStyle = getComputedStyle(document.documentElement).getPropertyValue("--grid-strong");
  g.lineWidth = 1;
  g.beginPath();
  pts.forEach(([px, py], i) => (i ? g.lineTo(ox + px * s, oy + py * s) : g.moveTo(ox + px * s, oy + py * s)));
  g.stroke();
  $("iter").textContent = `ITERATION ${n}`;
}

// ---------------------------------------------------------------- boot
async function boot() {
  $("iso-pick").onclick = async () => setISO(await api().PickISO());
  $("refresh").onclick = () => refreshDrives(false);
  driveDD = dropdown($("drive-dd"), "drive", (v) => { state.sel = v; state.keep = !!(drive() && drive().persistence); state.finished = false; render(); });
  modeDD = dropdown($("mode-dd"), "mode", (v) => { state.keep = v === "keep"; state.finished = false; render(); });
  $("size").oninput = (e) => { state.size = +e.target.value; render(); };
  $("size-dec").onclick = () => step(-1);
  $("size-inc").onclick = () => step(1);
  $("write").onclick = openConfirm;
  $("c-cancel").onclick = () => { $("confirm").hidden = true; };
  $("c-ok").onclick = start;
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") $("confirm").hidden = true; });
  window.runtime.EventsOn("job", onJob);
  window.runtime.EventsOn("update", onUpdate);
  $("upd").onclick = () => { $("upd").disabled = true; $("upd-lbl").textContent = "Updating…"; api().InstallUpdate(); };
  const download = (extras) => { $("iso-dl").disabled = $("iso-dl-x").disabled = true; $("dl-meter").hidden = false; api().DownloadISO(extras); };
  $("iso-dl").onclick = () => download(false);
  $("iso-dl-x").onclick = () => download(true);
  if (window.runtime.OnFileDrop) {
    window.runtime.OnFileDrop(async (_x, _y, paths) => {
      const p = (paths || []).find((q) => q.toLowerCase().endsWith(".iso")) || (paths || [])[0];
      if (p && !state.running) setISO(await api().Inspect(p));
    }, false);
  }
  state.info = await api().Info();
  $("facts").textContent = `BACKPACK // ${state.info.os} // ${state.info.version}`;
  if (state.info.iso) state.iso = state.info.iso;
  await refreshDrives(false);
  drawDragon();
  checkUpdate();
  new ResizeObserver(() => { if ($("out").classList.contains("empty")) drawDragon(); }).observe($("out"));
}

window.addEventListener("DOMContentLoaded", boot);
