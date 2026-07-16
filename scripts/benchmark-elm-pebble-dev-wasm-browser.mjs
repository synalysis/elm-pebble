#!/usr/bin/env node
/**
 * Browser first-load comparison: elm-pages JS (`/`) vs WASM preview
 * (`/wasm-web/host/browser.html`) served from the same dist/.
 *
 * Usage:
 *   node scripts/benchmark-elm-pebble-dev-wasm-browser.mjs [dist-dir]
 *
 * Environment:
 *   BASE_URL   — if set, use existing server (skip spawn)
 *   PORT       — listen port when spawning (default: ephemeral)
 *   RUNS       — cold navigations per target/profile (default: 3)
 *   NETWORK    — off | fast3g | slow3g | all  (default: all)
 *   CACHE      — cold | warm | both           (default: both)
 */

import { spawn, spawnSync } from "node:child_process";
import { createServer } from "node:net";
import { pathToFileURL } from "node:url";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { access, writeFile } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..");
const distDir = resolve(process.argv[2] || join(repoRoot, "elm_pebble_dev/dist"));
const runs = Math.max(1, Number(process.env.RUNS || 3));

/** DevTools-style throttling (bytes/sec, RTT ms). */
const NETWORK_PROFILES = {
  off: null,
  fast3g: {
    downloadThroughput: Math.floor((1.6 * 1024 * 1024) / 8),
    uploadThroughput: Math.floor((750 * 1024) / 8),
    latency: 150,
  },
  slow3g: {
    downloadThroughput: Math.floor((500 * 1024) / 8),
    uploadThroughput: Math.floor((500 * 1024) / 8),
    latency: 400,
  },
};

function selectedNetworks() {
  const raw = (process.env.NETWORK || "all").toLowerCase();
  if (raw === "all") return ["off", "fast3g", "slow3g"];
  if (!(raw in NETWORK_PROFILES)) {
    throw new Error(`unknown NETWORK=${raw} (use off|fast3g|slow3g|all)`);
  }
  return [raw];
}

function selectedCaches() {
  const raw = (process.env.CACHE || "both").toLowerCase();
  if (raw === "both") return ["cold", "warm"];
  if (raw !== "cold" && raw !== "warm") {
    throw new Error(`unknown CACHE=${raw} (use cold|warm|both)`);
  }
  return [raw];
}

async function pathExists(p) {
  try {
    await access(p, fsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function freePort() {
  return await new Promise((resolvePort, reject) => {
    const srv = createServer();
    srv.listen(0, "127.0.0.1", () => {
      const { port } = srv.address();
      srv.close((err) => (err ? reject(err) : resolvePort(port)));
    });
  });
}

async function loadPlaywright() {
  try {
    return await import("playwright");
  } catch {
    // fall through
  }
  try {
    return await import(
      pathToFileURL(join(repoRoot, "elm_pebble_dev/node_modules/playwright/index.mjs")).href
    );
  } catch {
    // fall through
  }
  console.error(
    "playwright not found. Install with:\n  cd elm_pebble_dev && npm i -D playwright && npx playwright install chromium"
  );
  process.exit(2);
}

async function waitForServer(url, timeoutMs = 15000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(url, { method: "HEAD" });
      if (res.ok || res.status === 405 || res.status === 404) return;
    } catch {
      // retry
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error(`server not ready: ${url}`);
}

async function applyNetwork(page, profile) {
  const session = await page.context().newCDPSession(page);
  if (!profile) {
    await session.send("Network.emulateNetworkConditions", {
      offline: false,
      downloadThroughput: -1,
      uploadThroughput: -1,
      latency: 0,
    });
    return;
  }
  await session.send("Network.emulateNetworkConditions", {
    offline: false,
    downloadThroughput: profile.downloadThroughput,
    uploadThroughput: profile.uploadThroughput,
    latency: profile.latency,
  });
}

async function waitForAppReady(page, timeoutMs) {
  // Require the Document title from the app (not a static HTML placeholder) and
  // a filled <main> so async WASM/manifest fetches finish before warm-cache priming.
  await page.waitForFunction(
    () => typeof document.title === "string" && document.title.includes("Elm Pebble"),
    { timeout: timeoutMs }
  );
  await page.waitForFunction(
    () => {
      const main = document.querySelector("main");
      return Boolean(main && (main.innerText || "").trim().length > 20);
    },
    { timeout: timeoutMs }
  );
}

async function collectReadyMetrics(page, url, timeoutMs) {
  const t0 = performance.now();
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: timeoutMs });

  await page.waitForFunction(
    () => typeof document.title === "string" && document.title.includes("Elm Pebble"),
    { timeout: timeoutMs }
  );
  const title = await page.title();
  const titleMs = performance.now() - t0;

  await page.waitForFunction(
    () => {
      const main = document.querySelector("main");
      return Boolean(main && (main.innerText || "").trim().length > 20);
    },
    { timeout: timeoutMs }
  );
  const mainMs = performance.now() - t0;
  const mainText = await page.locator("main").innerText();

  const perf = await page.evaluate(() => {
    const nav = performance.getEntriesByType("navigation")[0];
    const paints = performance.getEntriesByType("paint");
    const fcp = paints.find((p) => p.name === "first-contentful-paint");
    const resources = performance.getEntriesByType("resource");
    let transferSize = 0;
    let encodedBodySize = 0;
    const byExt = { wasm: 0, js: 0, css: 0, json: 0, img: 0, other: 0 };
    const bump = (name, n) => {
      const u = name.toLowerCase();
      if (u.includes(".wasm")) byExt.wasm += n;
      else if (u.includes(".css")) byExt.css += n;
      else if (u.includes(".json")) byExt.json += n;
      else if (/\.(png|jpe?g|webp|gif|svg)(\?|$)/.test(u)) byExt.img += n;
      else if (u.includes(".js") || u.includes("javascript")) byExt.js += n;
      else byExt.other += n;
    };
    for (const r of resources) {
      const n = r.transferSize || 0;
      transferSize += n;
      encodedBodySize += r.encodedBodySize || 0;
      bump(r.name, n);
    }
    if (nav) {
      transferSize += nav.transferSize || 0;
      encodedBodySize += nav.encodedBodySize || 0;
      bump(location.href, nav.transferSize || 0);
    }
    return {
      domContentLoaded: nav ? nav.domContentLoadedEventEnd : null,
      loadEventEnd: nav ? nav.loadEventEnd : null,
      fcp: fcp ? fcp.startTime : null,
      transferSize,
      encodedBodySize,
      byExt,
      resourceCount: resources.length,
    };
  });

  const bootTiming = await page.evaluate(() => globalThis.__elmcBootTiming || null);

  return {
    title,
    title_ms: +titleMs.toFixed(1),
    main_ready_ms: +mainMs.toFixed(1),
    main_text_len: (mainText || "").trim().length,
    fcp_ms: perf.fcp != null ? +perf.fcp.toFixed(1) : null,
    dcl_ms: perf.domContentLoaded != null ? +perf.domContentLoaded.toFixed(1) : null,
    load_ms: perf.loadEventEnd != null ? +perf.loadEventEnd.toFixed(1) : null,
    transfer_size: perf.transferSize,
    encoded_body_size: perf.encodedBodySize,
    transfer_by_ext: perf.byExt,
    resource_count: perf.resourceCount,
    boot_timing: bootTiming,
  };
}

async function measureScenario(browser, url, label, networkName, cacheMode) {
  const profile = NETWORK_PROFILES[networkName];
  // Slow networks need more headroom.
  const timeoutMs = networkName === "slow3g" ? 180000 : networkName === "fast3g" ? 90000 : 60000;
  const samples = [];

  for (let i = 0; i < runs; i++) {
    const context = await browser.newContext({ bypassCSP: true });
    const page = await context.newPage();
    await applyNetwork(page, profile);

    if (cacheMode === "warm") {
      // Prime HTTP cache (including async WASM/manifest fetches), then measure reload.
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: timeoutMs });
      await waitForAppReady(page, timeoutMs);
    }

    const metrics = await collectReadyMetrics(page, url, timeoutMs);
    samples.push({
      label,
      network: networkName,
      cache: cacheMode,
      ...metrics,
    });

    await context.close();
  }

  return samples;
}

function avg(samples, key) {
  const nums = samples.map((s) => s[key]).filter((n) => typeof n === "number");
  if (!nums.length) return null;
  return +(nums.reduce((a, b) => a + b, 0) / nums.length).toFixed(1);
}

function sumAvg(samples, key) {
  const nums = samples.map((s) => s[key]).filter((n) => typeof n === "number");
  if (!nums.length) return null;
  return Math.round(nums.reduce((a, b) => a + b, 0) / nums.length);
}

function avgBootTiming(samples) {
  const timings = samples.map((s) => s.boot_timing).filter(Boolean);
  if (!timings.length) return null;
  const keys = [
    "total_ms",
    "fetch_ms",
    "compile_ms",
    "instantiate_ms",
    "entry_ms",
    "browser_boot_ms",
  ];
  const out = {
    compile_mode: timings[0].compile_mode ?? null,
  };
  for (const key of keys) {
    const nums = timings.map((t) => t[key]).filter((n) => typeof n === "number");
    out[key] = nums.length
      ? +(nums.reduce((a, b) => a + b, 0) / nums.length).toFixed(1)
      : null;
  }
  const phaseSamples = timings.map((t) => t.browser_boot_phases).filter(Boolean);
  if (phaseSamples.length) {
    const phaseKeys = Object.keys(phaseSamples[0]);
    const phases = {};
    for (const key of phaseKeys) {
      const nums = phaseSamples.map((p) => p[key]).filter((n) => typeof n === "number");
      phases[key] = nums.length
        ? +(nums.reduce((a, b) => a + b, 0) / nums.length).toFixed(2)
        : null;
    }
    out.phases = phases;
  }
  return out;
}

function summarize(samples) {
  return {
    title_ms: avg(samples, "title_ms"),
    main_ready_ms: avg(samples, "main_ready_ms"),
    fcp_ms: avg(samples, "fcp_ms"),
    dcl_ms: avg(samples, "dcl_ms"),
    transfer_size: sumAvg(samples, "transfer_size"),
    encoded_body_size: sumAvg(samples, "encoded_body_size"),
    transfer_by_ext: samples[0]?.transfer_by_ext,
    title: samples[0]?.title,
    main_text_len: samples[0]?.main_text_len,
    boot_timing: avgBootTiming(samples),
  };
}

function ratio(a, b) {
  if (!a || !b) return null;
  return +(a / b).toFixed(2);
}

async function main() {
  if (!(await pathExists(join(distDir, "index.html")))) {
    console.error(`missing ${distDir}/index.html — run elm-pages build first`);
    process.exit(1);
  }
  if (!(await pathExists(join(distDir, "wasm-web/host/browser.html")))) {
    console.error(`missing wasm-web host — run npm run build:wasm first`);
    process.exit(1);
  }

  const networks = selectedNetworks();
  const caches = selectedCaches();

  spawnSync(
    "python3",
    [
      "-c",
      `
from pathlib import Path
import brotli
root = Path(${JSON.stringify(distDir)})
for pattern in ["elm.*.js", "assets/*.js", "assets/*.css"]:
    for p in root.glob(pattern):
        br = p.with_name(p.name + ".br")
        if br.exists() and br.stat().st_mtime >= p.stat().st_mtime:
            continue
        br.write_bytes(brotli.compress(p.read_bytes(), quality=11))
        print(f"precompress {br.relative_to(root)}")
`,
    ],
    { stdio: "inherit" }
  );

  let baseUrl = process.env.BASE_URL || null;
  let child = null;

  if (!baseUrl) {
    const port = Number(process.env.PORT || (await freePort()));
    const serveScript = join(repoRoot, "scripts/serve-static-brotli.py");
    child = spawn(
      "python3",
      [
        serveScript,
        distDir,
        "--port",
        String(port),
        "--bind",
        "127.0.0.1",
        // Stable wasm-web URLs need explicit long cache for warm runs.
        "--immutable-cache",
      ],
      {
        stdio: ["ignore", "pipe", "pipe"],
      }
    );
    baseUrl = `http://127.0.0.1:${port}`;
    await waitForServer(`${baseUrl}/`);
  }

  const { chromium } = await loadPlaywright();
  const browser = await chromium.launch({ headless: true });

  try {
    const jsUrl = `${baseUrl.replace(/\/$/, "")}/`;
    const wasmUrl = `${baseUrl.replace(/\/$/, "")}/wasm-web/host/browser.html`;

    const matrix = [];
    for (const network of networks) {
      for (const cache of caches) {
        console.error(`… measuring network=${network} cache=${cache}`);
        const jsSamples = await measureScenario(browser, jsUrl, "js", network, cache);
        const wasmSamples = await measureScenario(browser, wasmUrl, "wasm", network, cache);
        const js = summarize(jsSamples);
        const wasm = summarize(wasmSamples);
        matrix.push({
          network,
          cache,
          js,
          wasm,
          main_ready_ratio_wasm_over_js: ratio(wasm.main_ready_ms, js.main_ready_ms),
          transfer_ratio_wasm_over_js: ratio(wasm.transfer_size, js.transfer_size),
          samples: { js: jsSamples, wasm: wasmSamples },
        });
      }
    }

    const summary = {
      runs,
      base_url: baseUrl,
      networks,
      caches,
      matrix: matrix.map(({ samples: _s, ...row }) => row),
      samples: matrix,
    };

    console.log("=== browser first-load matrix (playwright averages) ===");
    console.log(
      JSON.stringify(
        {
          runs,
          networks,
          caches,
          matrix: summary.matrix.map((row) => ({
            network: row.network,
            cache: row.cache,
            js_main_ms: row.js.main_ready_ms,
            wasm_main_ms: row.wasm.main_ready_ms,
            main_ratio: row.main_ready_ratio_wasm_over_js,
            js_transfer: row.js.transfer_size,
            wasm_transfer: row.wasm.transfer_size,
            transfer_ratio: row.transfer_ratio_wasm_over_js,
            wasm_boot: row.wasm.boot_timing,
          })),
        },
        null,
        2
      )
    );

    const outPath = join(distDir, "wasm-web/wasm/browser_bench.json");
    await writeFile(outPath, JSON.stringify(summary, null, 2) + "\n");
    console.log(`wrote ${outPath}`);
  } finally {
    await browser.close();
    if (child) child.kill("SIGTERM");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
