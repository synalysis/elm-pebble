#!/usr/bin/env node
/**
 * Playwright smoke: client navigation fetches route bytes and updates title.
 *
 * Usage:
 *   node wasm_browser_playwright_nav_probe_runner.mjs <serveRoot> <linkSelector> <expectedTitle>
 *
 * serveRoot must contain index.html, wasm-web/, and target route HTML (e.g.
 * getting-started/index.html) for runtime route-byte fetch.
 */

import { spawn } from "node:child_process";
import { createServer as createNetServer } from "node:net";
import { request as httpRequest } from "node:http";
import { access, constants as fsConstants } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../../..");

const [serveRootArg, linkSelector, expectedTitle] = process.argv.slice(2);
const timeoutMs = Math.max(
  5000,
  Number(process.env.PLAYWRIGHT_TIMEOUT_MS || 90_000)
);

if (!serveRootArg || !linkSelector || !expectedTitle) {
  console.error(
    "usage: wasm_browser_playwright_nav_probe_runner.mjs <serveRoot> <linkSelector> <expectedTitle>"
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
  return await import(
    pathToFileURL(
      join(repoRoot, "elm_pebble_dev/node_modules/playwright/index.mjs")
    ).href
  );
}

async function main() {
  const browserHtml = join(serveRoot, "wasm-web/host/browser.html");
  if (!(await pathExists(browserHtml))) {
    console.error(`playwright nav probe failed: missing ${browserHtml}`);
    process.exit(1);
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
    await waitForServer(`${baseUrl}/`);
  }

  const { chromium } = await loadPlaywright();
  const browser = await chromium.launch({ headless: true });

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

    await page.waitForFunction(
      () => {
        const main = document.querySelector("main");
        return Boolean(main && (main.innerText || "").trim().length > 20);
      },
      { timeout: timeoutMs }
    );

    const link = resolveLinkLocator(page, linkSelector);
    await link.first().waitFor({ state: "visible", timeout: timeoutMs });

    if ((await link.count()) === 0) {
      const hrefs = await page.evaluate(() =>
        [...document.querySelectorAll("a")].map((a) => a.getAttribute("href"))
      );
      console.error(`link not found: ${linkSelector}`);
      console.error(`anchors: ${JSON.stringify(hrefs.slice(0, 20))}`);
      process.exit(1);
    }

    const initialTitle = await page.title();
    if (!initialTitle || initialTitle === "Page Data Error") {
      console.error(`boot title invalid: ${JSON.stringify(initialTitle)}`);
      process.exit(1);
    }

    const linkHandle = link.first();
    await Promise.all([
      page.waitForFunction(
        (title) => document.title === title,
        expectedTitle,
        { timeout: timeoutMs }
      ),
      linkHandle.click(),
    ]);

    const finalTitle = await page.title();
    if (finalTitle !== expectedTitle) {
      console.error(
        `title after nav: got ${JSON.stringify(finalTitle)}, expected ${JSON.stringify(expectedTitle)}`
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

    console.log(
      `rc_ok playwright_nav initial=${JSON.stringify(initialTitle)} final=${JSON.stringify(finalTitle)}`
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

function resolveLinkLocator(page, selector) {
  if (selector.startsWith("text:")) {
    return page.getByRole("link", { name: selector.slice(5) });
  }
  if (selector.startsWith("text=/") && selector.endsWith("/")) {
    const pattern = selector.slice(6, -1);
    return page.getByRole("link", { name: new RegExp(pattern) });
  }
  return page.locator(selector);
}
