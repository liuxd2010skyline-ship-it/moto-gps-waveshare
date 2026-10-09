"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { spawn } = require("node:child_process");
const { chromium } = require(require.resolve("playwright", { paths: [
  "C:/Users/pc/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules"] }));
async function main() {
  const browser = await chromium.launch({ executablePath: "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe", headless: true,
    args: ["--no-sandbox", "--disable-gpu", "--disable-gpu-sandbox"] });
  try {
    const page = await browser.newPage({ viewport: { width: 1040, height: 900 }, reducedMotion: "no-preference" });
    const errors = [];
    page.on("pageerror", e => errors.push(e.message));
    await page.goto(pathToFileURL(path.join(__dirname, "nav-ambient-motion-demo.html")).href);
    await page.waitForFunction(() => document.querySelector("#screen").dataset.ready === "true");
    await page.locator("#intensity").fill("72");
    await page.waitForFunction(() => document.querySelector("#intensity-value").value === "72");
    await page.locator("#intensity").fill("62");
    await page.locator("#speed").fill("75");
    await page.locator("#travel").fill("85");
    await page.locator('[data-scene="full-design-fixture"]').click();
    await page.waitForFunction(() => document.querySelector("#status").textContent.includes("RICH"));
    await page.screenshot({ path: path.join(__dirname, "nav-ambient-lab-full-check.png"), fullPage: true });
    await page.locator("#event").click();
    await page.locator("#freeze").click();
    if (await page.locator("#freeze").getAttribute("aria-pressed") !== "true") throw new Error("Pause failed");
    async function capture(scene, t, mode = "rgb24") {
      await page.evaluate(async ({scene,t,mode}) => {
        await NavAmbientPreview.renderAt(t, scene, mode, 8293);
      }, {scene,t,mode});
      // Export the actual 466 px raster. Locator screenshots can round a
      // fractional layout origin outward and introduce an extra pixel row.
      const dataURL = await page.locator("#screen").evaluate(canvas => canvas.toDataURL("image/png"));
      return Buffer.from(dataURL.split(",")[1], "base64");
    }
    for (const scene of ["route-only", "roads-only", "rich-fixture", "full-design-fixture"]) {
      fs.writeFileSync(path.join(__dirname, `nav-ambient-lab-${scene}-466.png`), await capture(scene, 0));
    }
    for (const mode of ["rgb24", "rgb565-plain", "rgb565-dither"]) {
      fs.writeFileSync(path.join(__dirname, `nav-ambient-lab-${mode}-466.png`), await capture("route-only", 0, mode));
    }
    await capture("route-only", 0);
    const routePixel = await page.evaluate(() => Array.from(
      document.querySelector('#screen').getContext('2d').getImageData(207,200,1,1).data));
    if (routePixel.join(',') !== '243,244,239,255') throw new Error(`Route color drift: ${routePixel}`);
    const python = "C:/Users/pc/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe";
    const frameCount = 128;
    const child = spawn(python, [path.join(__dirname,"encode_nav_ambient_lab.py"), __dirname, String(frameCount)], {stdio:["pipe","inherit","inherit"]});
    const done = new Promise((resolve,reject) => { child.on("error",reject); child.on("close",c => c === 0 ? resolve() : reject(new Error(`Encoder ${c}`))); });
    for (let i=0;i<frameCount;i++) {
      const png=await capture("route-only", i/8);
      const size=Buffer.alloc(4);size.writeUInt32LE(png.length);
      child.stdin.write(size);child.stdin.write(png);
    }
    child.stdin.end();await done;
    // The second native SVG entry point must also support variable patch IDs.
    await page.goto(pathToFileURL(path.join(__dirname, "nav-code-ready-v1.html")).href);
    await page.locator('svg').waitFor();
    const firstFrame = await page.locator('#artboard').innerHTML();
    await page.waitForTimeout(550);
    if (firstFrame === await page.locator('#artboard').innerHTML()) throw new Error('Native SVG animation did not advance');
    if(errors.length) throw new Error(errors.join("; "));
    console.log("Browser controls, design colors, full-data fusion, SVG entry point and 128 native frames verified.");
  } finally { await browser.close(); }
}
main().catch(e=>{console.error(e);process.exitCode=1;});
