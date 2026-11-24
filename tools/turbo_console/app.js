"use strict";
(() => {
const el = (tag, cls, text) => {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined) node.textContent = text;
  return node;
};
const pad = (v, n) => String(v).padEnd(n).slice(0, n);
const padl = (v, n) => String(v).padStart(n).slice(-n);
const bar = (f, w) => {
  const n = Math.round(Math.max(0, Math.min(1, f)) * w);
  return "█".repeat(n) + "░".repeat(w - n);
};
const line = (...parts) => {
  const row = el("div", "ln");
  for (const part of parts) {
    if (Array.isArray(part)) row.appendChild(el("span", part[0], part[1]));
    else row.appendChild(document.createTextNode(part));
  }
  return row;
};
const fmt = (n) => Number(n).toLocaleString("en-US");
const clock = (seconds) => {
  if (!isFinite(seconds) || seconds < 0) return "-";
  if (seconds > 86400) return ">1d";
  return new Date(seconds * 1000).toISOString().substr(11, 8);
};
const stateTone = (word) => (word === "running" ? "good" : word === "done" ? "note" : word === "waiting" ? "warn" : "bad");
const cell = (tone, label, value, sub) => {
  const node = el("div", "cell " + tone);
  node.appendChild(el("div", "lab", label));
  node.appendChild(el("div", "big", value));
  node.appendChild(el("div", "sub", sub));
  return node;
};
const fill = (id, rows) => {
  const body = document.querySelector("#" + id + " .body");
  body.replaceChildren(...rows);
};
const render = (s) => {
  document.getElementById("stamp").textContent = new Date(s.now).toLocaleTimeString();
  const state = document.getElementById("state");
  state.textContent = "live";
  state.className = "tag good";
  const gpuPercent = s.gpu ? s.gpu.percent : 0;
  const strip = document.getElementById("strip");
  strip.replaceChildren(
    cell(s.free ? "good" : "warn", "gate", s.free ? "free" : "busy", s.free ? "slices may run" : "the game has the machine"),
    cell(s.load[0] < s.load_limit ? "good" : "warn", "load 1m", s.load[0].toFixed(1), "limit " + s.load_limit + " of " + s.threads + " threads"),
    cell(s.gpu ? (gpuPercent < s.gpu_limit ? "good" : "warn") : "mute", "gpu", s.gpu ? gpuPercent + "%" : "-", "limit " + s.gpu_limit + "%"),
    cell("note", "levels", String(s.runs.length), s.runs.map((r) => r.level).join(" ") || "none"));
  const g = [
    line(pad("load 1m", 9), [s.load[0] < s.load_limit ? "good" : "warn", bar(s.load[0] / s.threads, 20)], " ", padl(s.load[0].toFixed(1), 5), " / ", String(s.load_limit)),
    line(pad("load 5m", 9), ["mute", bar(s.load[1] / s.threads, 20)], " ", padl(s.load[1].toFixed(1), 5)),
    line(pad("load 15m", 9), ["mute", bar(s.load[2] / s.threads, 20)], " ", padl(s.load[2].toFixed(1), 5))];
  g.push(s.gpu
    ? line(pad("gpu", 9), [gpuPercent < s.gpu_limit ? "good" : "warn", bar(gpuPercent / 100, 20)], " ", padl(gpuPercent, 5), "% / ", String(s.gpu_limit))
    : line(["mute", "no gpu reading"]));
  if (s.gpu) g.push(line(pad("gpu mem", 9), ["mute", bar(s.gpu.memory_used / s.gpu.memory_total, 20)], " ", fmt(s.gpu.memory_used), " of ", fmt(s.gpu.memory_total), " MiB"));
  g.push(line(""), line(["mute", "A slice starts only when both gauges are under their limits."]));
  fill("p1", g);
  fill("p2", s.runs.length ? s.runs.flatMap((r) => {
    const ref = r.reference;
    const f = ref ? r.nodes / ref.nodes : 0;
    const left = ref && r.rate ? (ref.nodes - r.nodes) / r.rate : NaN;
    return [
      line(pad(r.level, 6), [stateTone(r.state), pad(r.state, 8)], [stateTone(r.state), bar(f, 24)], " ", padl((f * 100).toFixed(1), 5), "%"),
      line(pad("", 6), ["mute", "nodes "], fmt(r.nodes), ref ? " of " + fmt(ref.nodes) + " (Turbo)" : "", ["mute", "  slices "], fmt(r.slices)),
      line(pad("", 6), ["mute", "rate "], r.rate + " nodes/s", ["mute", "  left "], clock(left), ["mute", "  objective "], r.objective === null ? "-" : String(r.objective), ref ? " (Turbo " + ref.objective + ")" : ""),
      line("")];
  }) : [line(["mute", "no player logs in the run folder yet"])]);
  fill("p3", s.runs.length ? s.runs.flatMap((r) => [
    line([stateTone(r.state), pad(r.level, 6)], ["mute", "turbo_solve · solve-level"]),
    line(pad("", 6), ...(r.plan.length ? r.plan.flatMap((step, i) => (i ? [["mute", " → "], ["note", step]] : [["note", step]])) : [["mute", "nothing left to plan"]])),
    line("")]) : [line(["mute", "no plan yet"])]);
  fill("p4", s.runs.flatMap((r) => r.tail.map((l) => line([stateTone(r.state), pad(r.level, 6)], ["mute", l]))));
};
const tick = async () => {
  try {
    render(await (await fetch("/api/status", { cache: "no-store" })).json());
  } catch (e) {
    const state = document.getElementById("state");
    state.textContent = "unreachable";
    state.className = "tag bad";
  }
};
let zoomed = null;
const zoom = (id) => {
  for (const p of document.querySelectorAll(".pane")) p.classList.toggle("zoom", p.id === id);
  zoomed = id;
};
document.addEventListener("keydown", (e) => {
  if (e.key >= "1" && e.key <= "4") zoom("p" + e.key);
  else if (e.key === "Escape") zoom(null);
  else if (e.key === "t") document.documentElement.dataset.theme = document.documentElement.dataset.theme === "observatory" ? "light" : "observatory";
  else if (e.key === "r") tick();
});
tick();
setInterval(tick, 2000);
})();
