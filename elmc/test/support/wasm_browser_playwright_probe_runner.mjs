#!/usr/bin/env node
/**
 * Playwright smoke: load dist/wasm-web/host/browser.html over HTTP and wait for
 * the Elm document title + main content (real browser boot path).
 *
 * Usage:
 *   node wasm_browser_playwright_probe_runner.mjs <serveRoot> [expectedTitle]
 *
 * serveRoot must contain:
 *   - index.html (elm-pages; page bytes + styles)
 *   - wasm-web/host/browser.html
 *   - wasm-web/wasm/app.wasm
 *
 * Environment:
 *   PLAYWRIGHT_TIMEOUT_MS — default 60000
 *   BASE_URL — skip server spawn (must already serve serveRoot)
 */

import { spawn, spawnSync } from "node:child_process";
import { createServer as createNetServer } from "node:net";
import { request as httpRequest } from "node:http";
import { access, constants as fsConstants } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../../..");

const [serveRootArg, expectedTitleArg] = process.argv.slice(2);
const expectedTitle =
  expectedTitleArg ?? "Elm Pebble | Watch faces & apps in Elm";
const timeoutMs = Math.max(
  5000,
  Number(process.env.PLAYWRIGHT_TIMEOUT_MS || 60_000)
);

if (!serveRootArg) {
  console.error(
    "usage: wasm_browser_playwright_probe_runner.mjs <serveRoot> [expectedTitle]"
  );
  process.exit(2);
}

const serveRoot = resolve(serveRootArg);

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
    const srv = createNetServer();
    srv.listen(0, "127.0.0.1", () => {
      const { port } = srv.address();
      srv.close((err) => (err ? reject(err) : resolvePort(port)));
    });
  });
}

async function waitForServer(url, deadlineMs = 60_000) {
  const start = Date.now();
  const { hostname, port, pathname } = new URL(url);

  while (Date.now() - start < deadlineMs) {
    try {
      const status = await new Promise((resolve, reject) => {
        const req = httpRequest(
          { hostname, port, path: pathname || "/", method: "HEAD" },
          (res) => resolve(res.statusCode ?? 0)
        );
        req.on("error", reject);
        req.end();
      });

      if (status >= 200 && status < 500) return;
    } catch {
      // retry
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error(`server not ready: ${url}`);
}

async function loadPlaywright() {
  try {
    return await import("playwright");
  } catch {
    // fall through
  }
  try {
    return await import(
      pathToFileURL(
        join(repoRoot, "elm_pebble_dev/node_modules/playwright/index.mjs")
      ).href
    );
  } catch {
    // fall through
  }
  console.error(
    "playwright not found. Install with:\n  cd elm_pebble_dev && npm i -D playwright && npx playwright install chromium"
  );
  process.exit(2);
}

async function main() {
  const browserHtml = join(serveRoot, "wasm-web/host/browser.html");
  const wasmPath = join(serveRoot, "wasm-web/wasm/app.wasm");
  const indexHtml = join(serveRoot, "index.html");

  for (const [label, path] of [
    ["index.html", indexHtml],
    ["browser.html", browserHtml],
    ["app.wasm", wasmPath],
  ]) {
    if (!(await pathExists(path))) {
      console.error(`playwright probe failed: missing ${label}: ${path}`);
      process.exit(1);
    }
  }

  let baseUrl = process.env.BASE_URL || null;
  let child = null;

  if (!baseUrl) {
    const port = Number(process.env.PORT || (await freePort()));
    const serveScript = join(repoRoot, "scripts/serve-static-brotli.py");
    child = spawn(
      "python3",
      [serveScript, serveRoot, "--port", String(port), "--bind", "127.0.0.1"],
      { stdio: ["ignore", "pipe", "pipe"] }
    );
    baseUrl = `http://127.0.0.1:${port}`;
    await new Promise((r) => setTimeout(r, 300));
    await waitForServer(`${baseUrl}/`);
  }

  const { chromium } = await loadPlaywright();

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
  } catch (err) {
    const hint = spawnSync(
      "npx",
      ["playwright", "install", "chromium"],
      { cwd: join(repoRoot, "elm_pebble_dev"), stdio: "inherit" }
    );
    if (hint.status !== 0) {
      console.error(`playwright chromium launch failed: ${err}`);
      process.exit(1);
    }
    browser = await chromium.launch({ headless: true });
  }

  try {
    const pageUrl = `${baseUrl.replace(/\/$/, "")}/wasm-web/host/browser.html`;
    const context = await browser.newContext({ bypassCSP: true });
    const page = await context.newPage();

    page.on("console", (msg) => {
      if (msg.type() === "error") {
        console.error(`[browser console] ${msg.text()}`);
      }
    });

    await page.goto(pageUrl, { waitUntil: "domcontentloaded", timeout: timeoutMs });

    const bootError = page.locator("#boot-error:not([hidden])");
    if (await bootError.count()) {
      const text = await bootError.innerText();
      console.error(`boot error visible:\n${text}`);
      process.exit(1);
    }

    await page.waitForFunction(
      (title) =>
        typeof document.title === "string" && document.title.includes(title),
      expectedTitle,
      { timeout: timeoutMs }
    );

    const title = await page.title();
    if (title !== expectedTitle) {
      console.error(
        `title mismatch: got ${JSON.stringify(title)}, expected ${JSON.stringify(expectedTitle)}`
      );
      process.exit(1);
    }

    await page.waitForFunction(
      () => {
        const main = document.querySelector("main");
        return Boolean(main && (main.innerText || "").trim().length > 20);
      },
      { timeout: timeoutMs }
    );

    const mainText = (await page.locator("main").innerText()).trim();
    const bootTiming = await page.evaluate(() => globalThis.__elmcBootTiming ?? null);

    console.log(
      `rc_ok playwright_title=${JSON.stringify(title)} main_len=${mainText.length} boot_timing=${JSON.stringify(bootTiming)}`
    );

    await context.close();
  } finally {
    await browser.close();
    if (child) child.kill("SIGTERM");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
