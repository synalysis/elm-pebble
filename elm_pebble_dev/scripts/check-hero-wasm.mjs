import { chromium } from "playwright";
import { readFileSync } from "node:fs";

const url = process.env.URL || "http://localhost:8080/wasm";
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
const logs = [];
page.on("console", (m) => {
  const t = m.text();
  if (/error|Error|RC imbalance|webgl|WebGL|fail/i.test(t)) {
    logs.push(m.type() + ": " + t.slice(0, 240));
  }
});
page.on("pageerror", (e) => logs.push("PAGEERROR: " + String(e.message).slice(0, 300)));

await page.goto(url, { waitUntil: "domcontentloaded", timeout: 90000 });
await page.waitForSelector("canvas", { timeout: 60000 });
await page.waitForTimeout(2000);

const canvas = page.locator("canvas").first();
await canvas.screenshot({ path: "/tmp/hero-canvas-a.png" });
await page.waitForTimeout(1800);
await canvas.screenshot({ path: "/tmp/hero-canvas-b.png" });
await page.screenshot({ path: "/tmp/hero-page.png" });

const analyze = async (path) =>
  page.evaluate(async (b64) => {
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const blob = new Blob([bytes], { type: "image/png" });
    const bmp = await createImageBitmap(blob);
    const c = document.createElement("canvas");
    c.width = bmp.width;
    c.height = bmp.height;
    const ctx = c.getContext("2d");
    ctx.drawImage(bmp, 0, 0);
    const { data, width, height } = ctx.getImageData(0, 0, c.width, c.height);
    let n = 0,
      sumSat = 0,
      nonClear = 0,
      rSum = 0,
      gSum = 0,
      bSum = 0;
    let hash = 0;
    for (let i = 0; i < data.length; i += 16) {
      const r = data[i],
        g = data[i + 1],
        b = data[i + 2],
        a = data[i + 3];
      hash = (hash * 33 + r + g * 3 + b * 7 + a) >>> 0;
      if (a < 8) continue;
      const nearClear =
        Math.abs(r - 15) < 18 && Math.abs(g - 23) < 18 && Math.abs(b - 41) < 28;
      const nearBlack = r + g + b < 24;
      if (nearClear || nearBlack) continue;
      nonClear++;
      rSum += r;
      gSum += g;
      bSum += b;
      const max = Math.max(r, g, b),
        min = Math.min(r, g, b);
      const sat = max === 0 ? 0 : (max - min) / max;
      sumSat += sat;
      n++;
    }
    return {
      wh: [width, height],
      nonClear,
      meanSat: n ? sumSat / n : 0,
      meanRgb: n
        ? [+(rSum / n).toFixed(1), +(gSum / n).toFixed(1), +(bSum / n).toFixed(1)]
        : null,
      sampleN: n,
      hash,
    };
  }, readFileSync(path).toString("base64"));

const a = await analyze("/tmp/hero-canvas-a.png");
const b = await analyze("/tmp/hero-canvas-b.png");
console.log(
  JSON.stringify({ a, b, motion: a.hash !== b.hash, logs: logs.slice(0, 25) }, null, 2)
);
await browser.close();
