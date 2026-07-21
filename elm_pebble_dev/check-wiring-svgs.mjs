import { chromium } from "playwright";

const url = process.argv[2] || "http://localhost:8080/wasm-web/host/browser.html";
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
const logs = [];
page.on("console", (msg) => logs.push([msg.type(), msg.text()]));
page.on("pageerror", (err) => logs.push(["pageerror", err.message]));
await page.goto(url, { waitUntil: "domcontentloaded", timeout: 90000 });
await page.waitForTimeout(4000);
const data = await page.evaluate(() => {
  const svgs = [...document.querySelectorAll("svg")].map((svg) => ({
    viewBox: svg.getAttribute("viewBox"),
    width: svg.getAttribute("width"),
    height: svg.getAttribute("height"),
    childCount: svg.children.length,
    innerHTML: svg.innerHTML.slice(0, 300),
    rects: [...svg.querySelectorAll("rect")].slice(0, 8).map((r) => ({
      x: r.getAttribute("x"),
      y: r.getAttribute("y"),
      w: r.getAttribute("width"),
      h: r.getAttribute("height"),
    })),
    texts: [...svg.querySelectorAll("text")].map((t) => t.textContent),
    paths: svg.querySelectorAll("path").length,
  }));
  return {
    title: document.title,
    svgCount: svgs.length,
    svgs,
  };
});
console.log(JSON.stringify(data, null, 2));
for (const [type, text] of logs) {
  if (
    type === "pageerror" ||
    String(text).includes("RC imbalance") ||
    String(text).toLowerCase().includes("error")
  ) {
    console.log("LOG", type, text);
  }
}
await browser.close();
