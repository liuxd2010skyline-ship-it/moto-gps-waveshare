/* MOTO GPS V6/B reference renderer. Illustrative fixtures, not map data.
 * Input points are projected 466 px coordinates from NavPresenter. All route
 * points must be the untravelled portion of the matched route.
 */
(function (root) {
  "use strict";

  const W = 466;
  const rider = { x: 207, y: 300 };
  const palette = typeof module !== "undefined" && module.exports
    ? require("./nav-design-palette.js") : root.NavDesignPalette;
  if (!palette) throw new Error("Load nav-design-palette.js before the renderer");
  const colors = palette.colors;
  const layout = Object.freeze({
    riderX: 207, riderY: 300, routeWidth: 12, routeUnderlayWidth: 18,
    fadeStart: 294, fadeEnd: 350, hudBaseline: 392,
    speedX: 350, speedY: 363, speedDiameter: 56
  });
  // The selected B material is one restrained graphite hue. It is a UI
  // texture, never a substitute for missing buildings or roads.
  const ambientMaterial = palette.ambientMaterial;
  const defaultAmbientSettings = Object.freeze({ intensity: 50, speed: 55, travel: 65, seed: 8293 });
  const ambientLimits = Object.freeze({ maxPatches: 4, opacityBudget: 1.9,
    minimumSpacing: 68, birthGap: [4.5, 8.5], lifetime: [14, 26] });
  function normalizeAmbientSettings(value) {
    const input = value && typeof value === "object" ? value : defaultAmbientSettings;
    const clamp = (number, fallback) => Number.isFinite(Number(number))
      ? Math.max(0, Math.min(100, Number(number))) : fallback;
    return {
      intensity: clamp(input.intensity, defaultAmbientSettings.intensity),
      speed: clamp(input.speed, defaultAmbientSettings.speed),
      travel: clamp(input.travel, defaultAmbientSettings.travel),
      seed: Number.isFinite(Number(input.seed)) ? Number(input.seed) >>> 0 : defaultAmbientSettings.seed
    };
  }

  const maneuverNames = Object.freeze({
    straight: "CONTINUE STRAIGHT", left: "TURN LEFT", right: "TURN RIGHT",
    slight_left: "BEAR LEFT", slight_right: "BEAR RIGHT",
    uturn: "MAKE A U-TURN", roundabout: "ROUNDABOUT", arrive: "ARRIVED"
  });
  const maneuverPaths = Object.freeze({
    right: '<path d="M20 61 V32 C20 27.5817 23.5817 24 28 24 H43" fill="none" stroke="currentColor" stroke-width="8.6" stroke-linecap="butt"/><polygon points="56,24 54.6,26.4 37.3,38.7 36.763,39.003 36.225,39.025 35.725,38.784 35.3,38.3 35.2,37.5 38.6,28.3 38.6,19.7 35.2,10.5 35.3,9.7 35.725,9.216 36.225,8.975 36.763,8.997 37.3,9.3 54.6,21.6"/>',
    left: '<path d="M52 61 V32 C52 27.5817 48.4183 24 44 24 H29" fill="none" stroke="currentColor" stroke-width="8.6" stroke-linecap="butt"/><polygon points="16,24 17.4,26.4 34.7,38.7 35.237,39.003 35.775,39.025 36.275,38.784 36.7,38.3 36.8,37.5 33.4,28.3 33.4,19.7 36.8,10.5 36.7,9.7 36.275,9.216 35.775,8.975 35.237,8.997 34.7,9.3 17.4,21.6"/>',
    straight: '<path d="M36 61 V27" fill="none" stroke="currentColor" stroke-width="8.6" stroke-linecap="butt"/><polygon points="36,10 54,29 50,32 40.3,28 31.7,28 22,32 18,29"/>',
    slight_right: '<path d="M20 61 V45 Q20 36 27 31 L43 17" fill="none" stroke="currentColor" stroke-width="8.6" stroke-linecap="butt"/><polygon points="55,7 53,29 48,30 42,22 35,16 36,11"/>',
    slight_left: '<path d="M52 61 V45 Q52 36 45 31 L29 17" fill="none" stroke="currentColor" stroke-width="8.6" stroke-linecap="butt"/><polygon points="17,7 19,29 24,30 30,22 37,16 36,11"/>',
    uturn: '<path d="M51 61 V31 Q51 16 36 16 Q21 16 21 31 V44" fill="none" stroke="currentColor" stroke-width="8.6" stroke-linecap="butt"/><polygon points="21,61 6,42 10,39 16,42 26,42 32,39 36,42"/>',
    roundabout: '<path d="M36 61 V52 A21 21 0 1 1 56 34" fill="none" stroke="currentColor" stroke-width="8.6" stroke-linecap="butt"/><polygon points="62,20 62,41 58,43 49,38 43,34 43,30"/>'
  });

  function finitePoint(p) {
    return p && Number.isFinite(p.x) && Number.isFinite(p.y);
  }
  function validRoute(s) {
    return s.geometryMatched === true && Array.isArray(s.routePoints) &&
      s.routePoints.length >= 2 && s.routePoints.length <= 24 &&
      s.routePoints.every(finitePoint) &&
      Math.hypot(s.routePoints[0].x - rider.x,
        s.routePoints[0].y - rider.y) <= 8;
  }
  function validGuidance(s) {
    return s.navState === "navigating" &&
      s.hasDestination === true && s.hasUsableFix === true &&
      s.gnssStale === false && s.hasNextManeuver === true &&
      maneuverNames[s.maneuver] !== undefined &&
      Number.isFinite(s.distanceToManeuverM) &&
      s.distanceToManeuverM >= 0 && s.offRoute !== true &&
      s.routeRequestInFlight !== true;
  }
  function selectScene(s) {
    if (s.phoneConnection !== "online") {
      return s.phoneConnection === "connecting" ? "PHONE_CONNECTING" : "PHONE_OFFLINE";
    }
    if (s.navState === "arrived") return "ARRIVED";
    if (!s.hasDestination) return "READY";
    if (s.offRoute || s.routeRequestInFlight || s.navState === "rerouting") return "REROUTING";
    if (!s.hasUsableFix || s.gnssStale) return "GPS_LOST";
    if (!validGuidance(s)) return "WAITING_ROUTE";
    if (!validRoute(s)) return "INSTRUCTION_ONLY";
    const roads = Array.isArray(s.roads) && s.roads.some(
      r => Array.isArray(r.points) && r.points.length >= 2);
    const buildings = Array.isArray(s.buildings) && s.buildings.some(
      b => Array.isArray(b.points) && b.points.length >= 3);
    return roads && buildings ? "RICH" : roads ? "ROADS_ONLY" : "ROUTE_ONLY";
  }
  function coord(n) { return Math.round(n * 100) / 100; }
  function smoothPath(points, maxRadius = 18) {
    if (!points || points.length < 2) return "";
    let d = `M ${coord(points[0].x)} ${coord(points[0].y)}`;
    for (let i = 1; i < points.length - 1; i++) {
      const a = points[i - 1], b = points[i], c = points[i + 1];
      const inLen = Math.hypot(b.x - a.x, b.y - a.y);
      const outLen = Math.hypot(c.x - b.x, c.y - b.y);
      if (inLen < 4 || outLen < 4) {
        d += ` L ${coord(b.x)} ${coord(b.y)}`;
        continue;
      }
      const ix = (b.x - a.x) / inLen, iy = (b.y - a.y) / inLen;
      const ox = (c.x - b.x) / outLen, oy = (c.y - b.y) / outLen;
      const dot = ix * ox + iy * oy;
      if (dot > 0.94 || dot < -0.8) {
        d += ` L ${coord(b.x)} ${coord(b.y)}`;
        continue;
      }
      const r = Math.min(maxRadius, inLen / 3, outLen / 3);
      d += ` L ${coord(b.x - ix * r)} ${coord(b.y - iy * r)}`;
      d += ` Q ${coord(b.x)} ${coord(b.y)} ${coord(b.x + ox * r)} ${coord(b.y + oy * r)}`;
    }
    const end = points[points.length - 1];
    return d + ` L ${coord(end.x)} ${coord(end.y)}`;
  }
  function escapeXML(text) {
    return String(text).replace(/[&<>"']/g, ch => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;"
    })[ch]);
  }
  function fmtDistance(m) {
    if (m >= 1000) {
      const km = m / 1000;
      return { value: (km < 10 ? km.toFixed(1) : Math.round(km).toString()), unit: "km" };
    }
    return { value: Math.round(m).toString(), unit: "m" };
  }
  function drawRoads(s) {
    if (!Array.isArray(s.roads)) return "";
    const styles = {
      motorway: [5.2, colors.roadMajor], primary: [5.2, colors.roadMajor],
      secondary: [3.9, colors.road], residential: [3.9, colors.road],
      service: [2.6, colors.roadMinor], other: [2.6, colors.roadMinor]
    };
    return s.roads.filter(r => Array.isArray(r.points) && r.points.length >= 2 &&
      r.points.every(finitePoint)).map(r => {
      const [width, color] = styles[r.class] || styles.other;
      const pts = r.points.map(p => `${coord(p.x)},${coord(p.y)}`).join(" ");
      return `<polyline points="${pts}" fill="none" stroke="${color}" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round"/>`;
    }).join("");
  }
  function drawBuildings(s) {
    if (!Array.isArray(s.buildings)) return "";
    return s.buildings.filter(b => Array.isArray(b.points) && b.points.length >= 3 &&
      b.points.every(finitePoint)).map(b => {
      const pts = b.points.map(p => `${coord(p.x)},${coord(p.y)}`).join(" ");
      const fill = b.class === "landmark" ? colors.buildingLandmark : colors.building;
      return `<polygon points="${pts}" fill="${fill}" stroke="${colors.buildingOutline}" stroke-width=".8"/>`;
    }).join("");
  }
  function drawRoute(s) {
    const d = smoothPath(s.routePoints);
    return `<path d="${d}" fill="none" stroke="${colors.routeUnderlay}" stroke-width="18" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="${d}" fill="none" stroke="${colors.route}" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>`;
  }
  function drawMarker() {
    // 48 x 54 source, calibrated to the selected 466 px V6 silhouette.
    // The route ends beneath the glyph; there is no visible travelled tail.
    return `<g transform="translate(176.3 264) scale(1.28)" aria-label="position and heading">
      <path d="M24 3.5 C24.6 3.5 25.1 3.9 25.4 4.6 L44.2 43.3 C45.3 45.7 43.4 47.4 41 46.4 L27.3 40.8 Q24 39.3 20.7 40.8 L7 46.4 C4.6 47.4 2.7 45.7 3.8 43.3 L22.6 4.6 C22.9 3.9 23.4 3.5 24 3.5 Z" fill="${colors.markerOutline}"/>
      <path d="M24 9.1 L39.2 41.7 L28.4 37.2 Q24 35.2 19.6 37.2 L8.8 41.7 Z" fill="${colors.route}"/></g>`;
  }
  function drawManeuver(type, x, y, size) {
    const path = maneuverPaths[type] || maneuverPaths.straight;
    const scale = size / 72;
    return `<g transform="translate(${x} ${y}) scale(${scale})" color="${colors.route}" fill="currentColor" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${path}</g>`;
  }
  function drawArc(progress) {
    const p = Math.max(0, Math.min(100, Number(progress) || 0));
    // Two restrained lower arcs follow the B concept; the active segment is
    // capped rather than inventing a speed/traffic signal.
    const d = "M105 416 Q233 481 361 416";
    return `<path d="${d}" fill="none" stroke="${colors.arc}" stroke-width="2.2" stroke-linecap="round"/><path d="${d}" pathLength="100" fill="none" stroke="${colors.arcActive}" stroke-width="2.6" stroke-linecap="round" stroke-dasharray="${p} 100"/>`;
  }
  function drawGuidance(s, scene) {
    const dist = fmtDistance(s.distanceToManeuverM);
    const showLimit = s.speedLimitValidated === true &&
      Number.isInteger(s.speedLimitKph) && s.speedLimitKph >= 10 &&
      s.speedLimitKph <= 130 && scene !== "INSTRUCTION_ONLY";
    const iconX = showLimit ? 105 : 125;
    const digitsX = showLimit ? 174 : 194;
    const valueFont = dist.value.length >= 4 ? 49 : 56;
    const digitsWidth = dist.value.length >= 4 ? 114 : dist.value.length === 3 ? 100 : 66;
    const unitX = digitsX + digitsWidth + 5;
    const instructionX = digitsX;
    let limit = "";
    if (showLimit) {
      limit = `<circle cx="350" cy="363" r="25.5" fill="${colors.limitFace}" stroke="${colors.red}" stroke-width="5.6"/><text x="350" y="372" text-anchor="middle" fill="${colors.limitText}" font-size="25" font-weight="700" class="screen-font">${s.speedLimitKph}</text>`;
    }
    return `${drawManeuver(s.maneuver, iconX, 342, 64)}
      <text x="${digitsX}" y="${layout.hudBaseline}" fill="${colors.route}" font-size="${valueFont}" font-weight="700" letter-spacing="-2.6" class="screen-font">${dist.value}</text>
      <text x="${unitX}" y="391" fill="${colors.unit}" font-size="20" font-weight="500" class="screen-font">${dist.unit}</text>
      <text x="${instructionX}" y="417" fill="${colors.textQuiet}" font-size="12" font-weight="650" letter-spacing="1.35" class="screen-font">${maneuverNames[s.maneuver]}</text>
      ${limit}${drawArc(s.routeProgressPercent)}`;
  }
  function drawStatus(scene) {
    const copy = {
      PHONE_OFFLINE: ["PHONE DISCONNECTED", "OPEN MOTO GPS ON YOUR PHONE"],
      PHONE_CONNECTING: ["CONNECTING TO PHONE", "KEEP YOUR PHONE NEARBY"],
      READY: ["READY TO RIDE", "CHOOSE A DESTINATION ON YOUR PHONE"],
      REROUTING: ["REROUTING", "WAITING FOR A NEW ROUTE"],
      GPS_LOST: ["GPS SIGNAL LOST", "WAITING FOR A FRESH POSITION"],
      WAITING_ROUTE: ["ROUTE UNAVAILABLE", "CHECK YOUR PHONE FOR DETAILS"],
      ARRIVED: ["ARRIVED", "YOUR RIDE IS COMPLETE"]
    }[scene] || ["WAITING", "CHECK YOUR PHONE"];
    return `<path d="M198 275 H268" fill="none" stroke="${colors.statusMark}" stroke-width="2" stroke-linecap="round"/>
      <path d="M233 265 V285" fill="none" stroke="${colors.statusMark}" stroke-width="2" stroke-linecap="round"/>
      <text x="233" y="342" text-anchor="middle" fill="${colors.route}" font-size="22" font-weight="650" letter-spacing=".2" class="screen-font">${copy[0]}</text>
      <text x="233" y="367" text-anchor="middle" fill="${colors.textQuiet}" font-size="11.5" font-weight="550" letter-spacing=".9" class="screen-font">${copy[1]}</text>
      <path d="M105 416 Q233 481 361 416" fill="none" stroke="${colors.arc}" stroke-width="2.2" stroke-linecap="round"/>`;
  }
  const ambientTimelines = new Map();
  function createAmbientTimeline(seed) {
    let randomState = seed >>> 0;
    const random = () => {
      randomState = (1664525 * randomState + 1013904223) >>> 0;
      return randomState / 4294967296;
    };
    const range = (a, b) => a + (b - a) * random();
    let nextBirth = -48;
    let sequence = 0;
    let lastSample = -Infinity;
    let events = [];
    let live = [];
    return {
      sample(t) {
        if (t < lastSample) return null;
        while (nextBirth <= t) {
          live = live.filter(p => p.start + p.life > nextBirth);
          if (live.length < ambientLimits.maxPatches) {
            let center = null;
            let kind = 0;
            for (let attempt = 0; attempt < 12; attempt++) {
              kind = Math.floor(random() * 3);
              const anchor = [[105, 104], [340, 165], [154, 249]][kind];
              const candidate = { x: anchor[0] + range(-48, 48),
                y: Math.max(54, Math.min(274, anchor[1] + range(-34, 34))) };
              if (live.every(p => Math.hypot(p.cx - candidate.x, p.cy - candidate.y) >= ambientLimits.minimumSpacing)) {
                center = candidate; break;
              }
            }
            if (center) {
              const template = [[100, 59, -17], [87, 97, 26], [104, 66, 11]][kind];
              const size = range(.83, 1.08);
              const patch = { id: sequence++, start: nextBirth,
                life: range(...ambientLimits.lifetime), fadeIn: range(2.8, 4.2),
                fadeOut: range(3.8, 5.8), peak: range(.52, .78),
                cx: center.x, cy: center.y, rx: template[0] * size,
                ry: template[1] * size, angle: template[2] + range(-12, 12),
                kind, phase: range(0, Math.PI * 2), driftX: range(12, 20),
                driftY: range(8, 14), periodX: range(5, 9), periodY: range(7, 12) };
              events.push(patch); live.push(patch);
            }
          }
          nextBirth += range(...ambientLimits.birthGap);
        }
        lastSample = t;
        events = events.filter(p => p.start + p.life > t);
        return events;
      }
    };
  }
  function lifecyclePatches(t, seed) {
    let timeline = ambientTimelines.get(seed);
    if (!timeline) timeline = createAmbientTimeline(seed);
    let patches = timeline.sample(t);
    if (!patches) { timeline = createAmbientTimeline(seed); patches = timeline.sample(t); }
    ambientTimelines.set(seed, timeline);
    // Preview captures can use multiple seeds, while cache memory stays bounded.
    if (ambientTimelines.size > 4) ambientTimelines.delete(ambientTimelines.keys().next().value);
    return patches;
  }
  function ambientAt(tSeconds, eventAgeSeconds, scene, reduceMotion,
    settings = defaultAmbientSettings) {
    const config = normalizeAmbientSettings(settings);
    const active = ["RICH", "ROADS_ONLY", "ROUTE_ONLY", "INSTRUCTION_ONLY"].includes(scene);
    // Status scenes retain the same material at a still position.  This
    // prevents movement from implying that a stale route is still active.
    const rate = config.speed === 0 ? 0 : .3 + config.speed * .014;
    const t = reduceMotion || !active ? 0 : Math.max(0, Number(tSeconds) || 0) * rate;
    const eventAge = Number(eventAgeSeconds);
    const response = reduceMotion || !active || !Number.isFinite(eventAge) ||
      eventAge < 0 || eventAge > 1.1
      ? 0 : Math.pow(1 - eventAge / 1.1, 2);
    const lift = .03 * response;
    // Randomness is sampled only at birth. Per-frame position and opacity
    // remain continuous; no random noise is introduced into each frame.
    const travelScale = config.travel / 65;
    const smoothstep = value => { const x = Math.max(0, Math.min(1, value)); return x * x * (3 - 2 * x); };
    const patches = lifecyclePatches(t, config.seed).map(p => {
      const age = t - p.start;
      const envelope = smoothstep(age / p.fadeIn) * smoothstep((p.life - age) / p.fadeOut);
      return { id: p.id, cx: coord(p.cx), cy: coord(p.cy), rx: coord(p.rx),
        ry: coord(p.ry), angle: coord(p.angle), kind: p.kind,
        dx: coord(travelScale * (p.driftX * Math.sin(age / p.periodX + p.phase) + 4 * Math.sin(age / 17))),
        dy: coord(travelScale * p.driftY * Math.sin(age / p.periodY + p.phase * .7)),
        opacity: envelope * (p.peak + lift) };
    }).filter(p => p.opacity > .003);
    const total = patches.reduce((sum, p) => sum + p.opacity, 0);
    const budgetScale = total > ambientLimits.opacityBudget ? ambientLimits.opacityBudget / total : 1;
    return patches.map(p => ({ ...p, opacity: Math.round(p.opacity * budgetScale * 10000) / 10000 }));
  }
  function ambientSemanticKey(s, scene = selectScene(s)) {
    // A distance packet does not change the key. A new route or instruction
    // does. MapScene density alone must not trigger a response. NavCore has
    // next_maneuver.id; the firmware adapter should carry that ID into UI.
    const stage = ["RICH", "ROADS_ONLY", "ROUTE_ONLY", "INSTRUCTION_ONLY"]
      .includes(scene) ? "NAVIGATING" : scene;
    return [stage, s.routeGeneration ?? "", s.routeId ?? "",
      s.nextManeuverId ?? s.maneuver ?? ""].join("|");
  }
  function proximityBand(distanceM) {
    if (!Number.isFinite(distanceM) || distanceM < 0) return 3;
    if (distanceM <= 30) return 0;
    if (distanceM <= 80) return 1;
    if (distanceM <= 200) return 2;
    return 3;
  }
  function createAmbientController() {
    let lastMs = null;
    let phaseSeconds = 0;
    let lastKey = null;
    let lowestBand = 3;
    let eventMs = -Infinity;
    return Object.freeze({
      sample(s, nowMs, reduceMotion = false) {
        const now = Number.isFinite(nowMs) ? Math.max(0, nowMs) : 0;
        const scene = selectScene(s);
        const active = ["RICH", "ROADS_ONLY", "ROUTE_ONLY", "INSTRUCTION_ONLY"].includes(scene);
        const key = ambientSemanticKey(s, scene);
        const band = proximityBand(s.distanceToManeuverM);
        if (lastMs !== null && active && !reduceMotion) {
          phaseSeconds += Math.max(0, Math.min(1000, now - lastMs)) / 1000;
        }
        if (lastKey !== null && active &&
          (key !== lastKey || band < lowestBand)) eventMs = now;
        lowestBand = key === lastKey ? Math.min(lowestBand, band) : band;
        lastKey = key;
        lastMs = now;
        return {
          scene, tSeconds: reduceMotion ? 0 : phaseSeconds,
          eventAgeSeconds: reduceMotion || !active ? Infinity : (now - eventMs) / 1000
        };
      }
    });
  }
  function ambientMarkup(phases) {
    return phases.map(p => {
      const gradient = ["diffuseA", "diffuseB", "diffuseC"][p.kind];
      return `<g id="ambient-patch-${p.id}" transform="translate(${p.cx + p.dx} ${p.cy + p.dy}) rotate(${p.angle})" opacity="${p.opacity}">
        <ellipse rx="${p.rx}" ry="${p.ry}" fill="url(#${gradient})"/>
        <ellipse cx="${coord(p.rx * -.32)}" cy="${coord(p.ry * .15)}" rx="${coord(p.rx * .46)}" ry="${coord(p.ry * .8)}" transform="rotate(35)" fill="url(#${gradient})"/>
      </g>`;
    }).join("");
  }
  function buildSVG(s, tSeconds = 0, eventAgeSeconds = Infinity,
    reduceMotion = false, settings = defaultAmbientSettings) {
    const scene = selectScene(s);
    const material = ambientMaterial;
    const config = normalizeAmbientSettings(settings);
    const strength = .25 + config.intensity * .015;
    const baseOpacity = coord(Math.max(.72, Math.min(.94,
      .86 + (config.intensity - 50) * .0014)));
    const alpha = value => coord(Math.min(.8, value * strength));
    const mapScene = ["RICH", "ROADS_ONLY", "ROUTE_ONLY"].includes(scene);
    const instructionOnly = scene === "INSTRUCTION_ONLY";
    const canShowGuidance = mapScene || instructionOnly;
    const validMapContext = mapScene;
    // The upper diffuse field is a UI material, never a cartographic object.
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${W}" viewBox="0 0 ${W} ${W}" role="img" aria-label="MOTO GPS ${scene}">
      <defs>
        <clipPath id="disc"><circle cx="233" cy="233" r="231"/></clipPath>
        <radialGradient id="ambient" cx=".41" cy=".28" r=".76"><stop offset="0" stop-color="${material.base}" stop-opacity="${baseOpacity}"/><stop offset=".54" stop-color="${material.mid}" stop-opacity=".56"/><stop offset="1" stop-color="${colors.black}" stop-opacity="1"/></radialGradient>
        <radialGradient id="diffuseA"><stop offset="0" stop-color="${material.a}" stop-opacity="${alpha(.29)}"/><stop offset=".6" stop-color="${material.aMid}" stop-opacity="${alpha(.13)}"/><stop offset="1" stop-color="${material.aMid}" stop-opacity="0"/></radialGradient>
        <radialGradient id="diffuseB"><stop offset="0" stop-color="${material.b}" stop-opacity="${alpha(.26)}"/><stop offset=".55" stop-color="${material.bMid}" stop-opacity="${alpha(.12)}"/><stop offset="1" stop-color="${material.bMid}" stop-opacity="0"/></radialGradient>
        <radialGradient id="diffuseC"><stop offset="0" stop-color="${material.c}" stop-opacity="${alpha(.21)}"/><stop offset=".55" stop-color="${material.c}" stop-opacity="${alpha(.10)}"/><stop offset="1" stop-color="${material.c}" stop-opacity="0"/></radialGradient>
        <linearGradient id="hudFade" x1="0" y1="294" x2="0" y2="350" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="${colors.black}" stop-opacity="0"/><stop offset=".42" stop-color="${colors.black}" stop-opacity=".45"/><stop offset="1" stop-color="${colors.black}" stop-opacity="1"/></linearGradient>
        <radialGradient id="edge" cx=".5" cy=".5" r=".5"><stop offset=".94" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".6"/></radialGradient>
      </defs>
      <style>.screen-font{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","PingFang SC","Helvetica Neue",Arial,sans-serif}</style>
      <circle cx="233" cy="233" r="233" fill="${colors.black}"/>
      <g clip-path="url(#disc)">
        <rect width="466" height="466" fill="url(#ambient)"/>
        ${ambientMarkup(ambientAt(tSeconds, eventAgeSeconds, scene, reduceMotion, config))}
        ${validMapContext ? drawBuildings(s) + drawRoads(s) + drawRoute(s) : ""}
        <rect x="0" y="294" width="466" height="56" fill="url(#hudFade)"/>
        <rect x="0" y="350" width="466" height="116" fill="${colors.black}"/>
        ${validMapContext ? drawMarker() : ""}
        ${canShowGuidance ? drawGuidance(s, scene) : drawStatus(scene)}
        ${instructionOnly ? `<text x="233" y="240" text-anchor="middle" fill="${colors.unavailable}" font-size="12" font-weight="600" letter-spacing="1.4" class="screen-font">MAP PREVIEW UNAVAILABLE</text>` : ""}
        <circle cx="233" cy="233" r="233" fill="url(#edge)"/>
      </g>
      <circle cx="233" cy="233" r="231.5" fill="none" stroke="${colors.edge}" stroke-width="1.2"/>
    </svg>`;
  }

  // Synthetic geometry exists only to inspect rendering states. It must never
  // be transported to the device or mistaken for Beijing map information.
  const sample = {
    phoneConnection: "online", navState: "navigating", hasDestination: true,
    hasUsableFix: true, gnssStale: false, offRoute: false,
    routeRequestInFlight: false, hasNextManeuver: true,
    maneuver: "right", nextManeuverId: 17, distanceToManeuverM: 300,
    routeProgressPercent: 38, speedLimitKph: 0, speedLimitValidated: false,
    geometryMatched: true,
    routePoints: [{ x: 207, y: 300 }, { x: 207, y: 153 },
      { x: 207, y: 132 }, { x: 231, y: 126 }, { x: 307, y: 126 },
      { x: 333, y: 110 }, { x: 353, y: 71 }],
    roads: [], buildings: []
  };
  function fullDesignFixture() {
    // Deliberately synthetic visual stress fixture. It exceeds the current
    // MapScene packet limit and is never transmitted as geographic data.
    const roads = [
      { class: "primary", points: [{ x: -10, y: 90 }, { x: 340, y: 90 }, { x: 478, y: 162 }] },
      { class: "residential", points: [{ x: -12, y: 165 }, { x: 306, y: 165 }, { x: 471, y: 218 }] },
      { class: "primary", points: [{ x: -10, y: 244 }, { x: 299, y: 244 }, { x: 470, y: 310 }] },
      { class: "residential", points: [{ x: -10, y: 306 }, { x: 209, y: 306 }, { x: 300, y: 285 }, { x: 474, y: 338 }] },
      { class: "residential", points: [{ x: 85, y: -10 }, { x: 85, y: 315 }] },
      { class: "primary", points: [{ x: 198, y: -12 }, { x: 198, y: 290 }] },
      { class: "residential", points: [{ x: 316, y: -10 }, { x: 316, y: 168 }, { x: 278, y: 257 }, { x: 310, y: 322 }] },
      { class: "primary", points: [{ x: 424, y: -10 }, { x: 380, y: 114 }, { x: 410, y: 245 }, { x: 344, y: 335 }] },
      { class: "service", points: [{ x: 20, y: 124 }, { x: 194, y: 124 }] },
      { class: "service", points: [{ x: 95, y: 206 }, { x: 306, y: 206 }] },
      { class: "service", points: [{ x: 342, y: 179 }, { x: 456, y: 235 }] },
      { class: "service", points: [{ x: 12, y: 279 }, { x: 84, y: 279 }] }
    ];
    const buildings = [];
    let seed = 8293;
    function next() { seed = (1664525 * seed + 1013904223) >>> 0; return seed / 4294967296; }
    const cols = [[13, 77], [96, 189], [210, 307], [328, 373], [389, 458]];
    const rows = [[13, 80], [101, 153], [175, 233], [254, 294]];
    for (const [top, bottom] of rows) {
      for (const [left, right] of cols) {
        let x = left + 3;
        while (x < right - 10) {
          const width = Math.min(right - x - 3, 14 + Math.floor(next() * 20));
          if (width < 9) break;
          let y = top + 4;
          while (y < bottom - 8) {
            const height = Math.min(bottom - y - 3, 13 + Math.floor(next() * 20));
            if (height < 8) break;
            const inset = next() > .6 ? 3 : 0;
            const points = inset ? [
              { x, y }, { x: x + width - inset, y },
              { x: x + width - inset, y: y + inset },
              { x: x + width, y: y + inset },
              { x: x + width, y: y + height }, { x, y: y + height }
            ] : [{ x, y }, { x: x + width, y },
              { x: x + width, y: y + height }, { x, y: y + height }];
            buildings.push({ points, class: next() > .94 ? "landmark" : "building" });
            y += height + 3 + Math.floor(next() * 4);
          }
          x += width + 3 + Math.floor(next() * 5);
        }
      }
    }
    return { roads, buildings };
  }
  function demoSnapshot(name) {
    const s = JSON.parse(JSON.stringify(sample));
    if (name === "short-route") {
      s.distanceToManeuverM = 38;
      s.maneuver = "left";
      s.routePoints = [{ x: 207, y: 300 }, { x: 207, y: 261 },
        { x: 193, y: 247 }, { x: 141, y: 247 }];
    } else if (name === "instruction-only") {
      s.geometryMatched = false;
      s.routePoints = [];
    } else if (name === "gps-lost") {
      s.gnssStale = true;
      s.hasUsableFix = false;
    } else if (name === "phone-offline") {
      s.phoneConnection = "offline";
    } else if (name === "rerouting") {
      s.navState = "rerouting";
      s.routeRequestInFlight = true;
    } else if (name === "no-destination") {
      s.hasDestination = false;
      s.hasNextManeuver = false;
      s.routePoints = [];
    } else if (name === "roads-only") {
      s.roads = [
        { class: "primary", points: [{ x: 28, y: 84 }, { x: 307, y: 84 }, { x: 442, y: 146 }] },
        { class: "residential", points: [{ x: 22, y: 205 }, { x: 331, y: 205 }, { x: 413, y: 266 }] },
        { class: "residential", points: [{ x: 96, y: 12 }, { x: 96, y: 285 }] },
        { class: "service", points: [{ x: 370, y: 16 }, { x: 272, y: 228 }] }
      ];
    } else if (name === "rich-fixture") {
      const roads = demoSnapshot("roads-only").roads;
      s.roads = roads;
      s.buildings = [
        { points: [{ x: 116, y: 103 }, { x: 151, y: 103 }, { x: 151, y: 146 }, { x: 116, y: 146 }] },
        { points: [{ x: 159, y: 105 }, { x: 185, y: 105 }, { x: 185, y: 144 }, { x: 159, y: 144 }] },
        { points: [{ x: 240, y: 143 }, { x: 279, y: 143 }, { x: 279, y: 187 }, { x: 240, y: 187 }] },
        { points: [{ x: 44, y: 101 }, { x: 78, y: 101 }, { x: 78, y: 143 }, { x: 44, y: 143 }] },
        { points: [{ x: 111, y: 220 }, { x: 164, y: 220 }, { x: 164, y: 261 }, { x: 111, y: 261 }] },
        { points: [{ x: 241, y: 220 }, { x: 284, y: 220 }, { x: 284, y: 260 }, { x: 241, y: 260 }] }
      ];
      s.speedLimitKph = 60;
      s.speedLimitValidated = true;
    } else if (name === "full-design-fixture") {
      const context = fullDesignFixture();
      s.roads = context.roads;
      s.buildings = context.buildings;
      s.speedLimitKph = 60;
      s.speedLimitValidated = true;
    }
    return s;
  }
  const api = Object.freeze({ colors, layout, ambientMaterial, defaultAmbientSettings, ambientLimits,
    normalizeAmbientSettings, selectScene, validRoute,
    validGuidance, smoothPath, ambientAt, ambientSemanticKey,
    createAmbientController, buildSVG, demoSnapshot,
    fmtDistance, escapeXML });
  root.NavCodeReadyV1 = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
