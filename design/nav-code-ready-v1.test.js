"use strict";
const assert = require("node:assert/strict");
const d = require("./nav-code-ready-v1.js");
const rgb565 = require("./nav-rgb565-preview.js");
const fs = require("node:fs");
const path = require("node:path");

function check(name, expected) {
  const actual = d.selectScene(d.demoSnapshot(name));
  assert.equal(actual, expected, `${name} scene`);
}
check("route-only", "ROUTE_ONLY");
check("short-route", "ROUTE_ONLY");
check("roads-only", "ROADS_ONLY");
check("rich-fixture", "RICH");
check("full-design-fixture", "RICH");
check("instruction-only", "INSTRUCTION_ONLY");
check("gps-lost", "GPS_LOST");
check("rerouting", "REROUTING");
check("phone-offline", "PHONE_OFFLINE");
check("no-destination", "READY");

const route = d.demoSnapshot("route-only");
const routeSvg = d.buildSVG(route);
assert.match(routeSvg, /TURN RIGHT/);
assert.match(routeSvg, /M 207 300/);
assert.doesNotMatch(routeSvg, /<polyline/);
assert.doesNotMatch(routeSvg, /stroke="#E83A43"/);
assert.doesNotMatch(routeSvg, /fill="#303335"/);
route.navState = "planning";
assert.equal(d.selectScene(route), "WAITING_ROUTE",
  "planning must not display retained guidance");
route.navState = "navigating";
route.networkOnline = false;
assert.equal(d.selectScene(route), "ROUTE_ONLY",
  "internet loss alone must not impersonate a phone disconnect");

const stale = d.demoSnapshot("gps-lost");
const staleSvg = d.buildSVG(stale);
assert.match(staleSvg, /GPS SIGNAL LOST/);
assert.doesNotMatch(staleSvg, />300</);
assert.doesNotMatch(staleSvg, /TURN RIGHT/);

const noGeometry = d.buildSVG(d.demoSnapshot("instruction-only"));
assert.match(noGeometry, /MAP PREVIEW UNAVAILABLE/);
assert.match(noGeometry, /TURN RIGHT/);
assert.doesNotMatch(noGeometry, /M 207 300/);

const limit = d.demoSnapshot("rich-fixture");
assert.match(d.buildSVG(limit), /stroke="#E83A43"/);
limit.speedLimitValidated = false;
assert.doesNotMatch(d.buildSVG(limit), /stroke="#E83A43"/);
const full = d.demoSnapshot("full-design-fixture");
assert.ok(full.buildings.length > 16, "complete visual target is explicitly beyond current packet capacity");
assert.equal(d.selectScene(full), "RICH");
assert.match(d.buildSVG(full), /stroke="#E83A43"/);

const before = d.ambientAt(0, Infinity, "ROUTE_ONLY", false);
const after = d.ambientAt(120, Infinity, "ROUTE_ONLY", false);
assert.notDeepEqual(before, after, "ambient must drift");
assert.deepEqual(d.ambientAt(0, Infinity, "ROUTE_ONLY", true),
  d.ambientAt(120, Infinity, "ROUTE_ONLY", true), "reduced motion must freeze");
assert.notDeepEqual(d.ambientAt(0, 0, "ROUTE_ONLY", false), before,
  "a key event must produce one restrained response");
assert.deepEqual(d.ambientAt(0, 2, "ROUTE_ONLY", false), before,
  "the key event response must settle without a repeated pulse");
assert.deepEqual(d.ambientAt(0, Infinity, "GPS_LOST", false),
  d.ambientAt(120, Infinity, "GPS_LOST", false),
  "status material must be still");
assert.ok(d.ambientAt(0, 0, "ROUTE_ONLY", false)[0].opacity - before[0].opacity <= .031,
  "a key event must not turn the material into a spotlight");
const preview = { intensity: 62, speed: 75, travel: 85 };
const frame0 = d.ambientAt(0, Infinity, "ROUTE_ONLY", false, preview);
const frame6 = d.ambientAt(6, Infinity, "ROUTE_ONLY", false, preview);
assert.notDeepEqual(frame6, frame0, "the lifecycle field must evolve over six real seconds");
assert.deepEqual(d.ambientAt(0, Infinity, "RICH", false, preview), frame0,
  "rich and route-only cases share one ambient layer");
const brighter = d.buildSVG(d.demoSnapshot("route-only"), 0, Infinity, false, preview);
assert.match(brighter, /TURN RIGHT/);
assert.match(brighter, /M 207 300/);
assert.notEqual(brighter, d.buildSVG(d.demoSnapshot("route-only")),
  "desktop intensity control must alter the background image");
assert.deepEqual(d.normalizeAmbientSettings({ intensity: -4, speed: 220, travel: 40 }),
  { intensity: 0, speed: 100, travel: 40, seed: 8293 });
const counts = new Set();
for (let t = 0; t <= 360; t += .5) {
  const patches = d.ambientAt(t, Infinity, "ROUTE_ONLY", false, preview);
  counts.add(patches.length);
  assert.ok(patches.length <= d.ambientLimits.maxPatches);
  assert.ok(patches.reduce((sum,p) => sum + p.opacity, 0) <= d.ambientLimits.opacityBudget + .0003);
}
assert.ok(counts.size > 1, "patch count must vary as random patches appear and disappear");
assert.notDeepEqual(d.ambientAt(8, Infinity, "ROUTE_ONLY", false, { ...preview, seed: 12 }),
  d.ambientAt(8, Infinity, "ROUTE_ONLY", false, { ...preview, seed: 13 }),
  "different session seeds must create different lifetime schedules");
const paletteHeader = fs.readFileSync(path.join(__dirname,"../shared/nav_ui/include/moto_map_visual_style.h"),"utf8");
const paletteSource = JSON.parse(fs.readFileSync(path.join(__dirname,
  "../shared/nav_ui/assets/nav_design_palette.json"), "utf8"));
for (const group of ["colors", "ambientMaterial"]) {
  for (const [key, value] of Object.entries(paletteSource[group])) {
    assert.equal(d[group][key], value.hex, `${key} must use the design source`);
    const hex = new RegExp(`MOTO_MAP_${value.token} = 0x([0-9A-Fa-f]{6})`).exec(paletteHeader)[1];
    assert.equal(value.hex.slice(1), hex.toUpperCase(), `${key} must match the firmware palette token`);
  }
}
// Birth/death envelopes must not introduce abrupt per-frame jumps.
let previous = new Map();
for (let t = 0; t < 50; t += 1 / 8) {
  const patches = d.ambientAt(t, Infinity, "ROUTE_ONLY", false, preview);
  const current = new Map(patches.map(p => [p.id, p]));
  for (const [id, p] of current) {
    const before = previous.get(id);
    if (before) assert.ok(Math.abs(p.opacity - before.opacity) < .09, "continuous opacity");
    else if (t > 0) assert.ok(p.opacity < .02, "new patches must enter close to transparent");
  }
  for (const [id, p] of previous) {
    if (!current.has(id)) assert.ok(p.opacity < .02, "patches must fade before removal");
  }
  previous = current;
}

const darkGradient = { width: 8, height: 8, data: new Uint8ClampedArray(8 * 8 * 4) };
for (let i = 0; i < darkGradient.data.length; i += 4) {
  darkGradient.data.set([29, 29, 29, 255], i);
}
const plain = rgb565.quantize({ width: 8, height: 8,
  data: darkGradient.data.slice() }, "rgb565-plain");
const dithered = rgb565.quantize({ width: 8, height: 8,
  data: darkGradient.data.slice() }, "rgb565-dither");
assert.equal(new Set(Array.from({ length: 64 }, (_, i) => plain.data[i * 4])).size, 1);
assert.ok(new Set(Array.from({ length: 64 }, (_, i) => dithered.data[i * 4])).size > 1,
  "fixed spatial dither must distribute an RGB565 boundary rather than form one flat band");
for (let i = 0; i < dithered.data.length; i += 4) {
  assert.equal(dithered.data[i],
    Math.round(Math.round(dithered.data[i] * 31 / 255) * 255 / 31));
}

const controller = d.createAmbientController();
const packets = d.demoSnapshot("route-only");
assert.equal(d.ambientSemanticKey(d.demoSnapshot("roads-only")),
  d.ambientSemanticKey(d.demoSnapshot("route-only")),
  "incoming map context must not look like a new navigation instruction");
assert.equal(controller.sample(packets, 0).eventAgeSeconds, Infinity);
packets.distanceToManeuverM = 299;
assert.equal(controller.sample(packets, 100).eventAgeSeconds, Infinity,
  "each distance packet must not trigger a light response");
packets.distanceToManeuverM = 200;
assert.equal(controller.sample(packets, 200).eventAgeSeconds, 0,
  "crossing an approach band triggers once");
packets.distanceToManeuverM = 205;
controller.sample(packets, 300);
packets.distanceToManeuverM = 199;
assert.equal(controller.sample(packets, 400).eventAgeSeconds, .2,
  "distance jitter around a threshold must not retrigger");
packets.routeGeneration = 2;
assert.equal(controller.sample(packets, 500).eventAgeSeconds, 0,
  "a route revision triggers once");
packets.nextManeuverId = 18;
assert.equal(controller.sample(packets, 550).eventAgeSeconds, 0,
  "a same-direction next maneuver still has its own identity");
packets.gnssStale = true;
assert.equal(controller.sample(packets, 600).eventAgeSeconds, Infinity,
  "GPS loss must not look like active navigation");
const frozenAt = controller.sample(packets, 700).tSeconds;
assert.equal(controller.sample(packets, 1200).tSeconds, frozenAt,
  "ambient phase pauses while GPS is stale");
assert.equal(controller.sample(packets, 1300, true).tSeconds, 0,
  "reduced motion fixes the material at its base frame");

console.log("MOTO GPS V6/B reference: all state, safety, geometry, and motion checks passed.");
