import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { RC_SUCCESS } from "../../../elmc-wasm-runtime/host/loader.js";
import { loadWasmFromBuildDir } from "./wasm_probe_manifest.js";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const buildDir = process.argv[2] || join(repoRoot, "elm_pebble_dev/dist/wasm-web");
const routeBytesPath =
  process.argv[3] || join(repoRoot, "elm_pebble_dev/dist/wasm/content.dat");

function installDomStubs() {
  const webglStats = {
    getContext: 0,
    clear: 0,
    drawArrays: 0,
    drawElements: 0,
    useProgram: 0,
  };

  const makeWebGl = () => {
    const gl = {
      ARRAY_BUFFER: 34962,
      ELEMENT_ARRAY_BUFFER: 34963,
      STATIC_DRAW: 35044,
      FLOAT: 5126,
      FLOAT_VEC2: 35664,
      FLOAT_VEC3: 35665,
      FLOAT_VEC4: 35666,
      FLOAT_MAT4: 35676,
      INT: 5124,
      BOOL: 35670,
      UNSIGNED_SHORT: 5123,
      UNSIGNED_INT: 5125,
      TRIANGLES: 4,
      COLOR_BUFFER_BIT: 16384,
      DEPTH_BUFFER_BIT: 256,
      STENCIL_BUFFER_BIT: 1024,
      DEPTH_TEST: 2929,
      BLEND: 3042,
      CULL_FACE: 2884,
      VERTEX_SHADER: 35633,
      FRAGMENT_SHADER: 35632,
      COMPILE_STATUS: 35713,
      LINK_STATUS: 35714,
      ACTIVE_ATTRIBUTES: 35721,
      ACTIVE_UNIFORMS: 35718,
      TEXTURE_2D: 3553,
      TEXTURE0: 33984,
      RGBA: 6408,
      UNSIGNED_BYTE: 5121,
      drawingBufferWidth: 720,
      drawingBufferHeight: 400,
      clear() {
        webglStats.clear += 1;
      },
      clearColor() {},
      clearDepth() {},
      clearStencil() {},
      enable() {},
      disable() {},
      viewport() {},
      depthMask() {},
      depthFunc() {},
      blendFunc() {},
      cullFace() {},
      frontFace() {},
      colorMask() {},
      stencilMask() {},
      stencilFunc() {},
      stencilOp() {},
      createBuffer() {
        return {};
      },
      bindBuffer() {},
      bufferData() {},
      createProgram() {
        return {};
      },
      createShader() {
        return {};
      },
      shaderSource() {},
      compileShader() {},
      attachShader() {},
      linkProgram() {},
      getProgramParameter(_prog, pname) {
        if (pname === 35718 || pname === 35721) return 0;
        return true;
      },
      getShaderParameter() {
        return true;
      },
      getActiveUniform() {
        return null;
      },
      getActiveAttrib() {
        return null;
      },
      getProgramInfoLog() {
        return "";
      },
      getShaderInfoLog() {
        return "";
      },
      useProgram() {
        webglStats.useProgram += 1;
      },
      getAttribLocation() {
        return 0;
      },
      getUniformLocation() {
        return {};
      },
      enableVertexAttribArray() {},
      vertexAttribPointer() {},
      uniform1i() {},
      uniform1f() {},
      uniform2f() {},
      uniform3f() {},
      uniform4f() {},
      uniformMatrix4fv() {},
      activeTexture() {},
      bindTexture() {},
      createTexture() {
        return {};
      },
      texImage2D() {},
      texParameteri() {},
      pixelStorei() {},
      drawArrays() {
        webglStats.drawArrays += 1;
      },
      drawElements() {
        webglStats.drawElements += 1;
      },
      getExtension() {
        return null;
      },
      getParameter() {
        return 0;
      },
    };
    // Scene3d touches a long tail of GL entry points; stub unknowns.
    return new Proxy(gl, {
      get(target, prop) {
        if (prop in target) return target[prop];
        if (typeof prop === "string") {
          const stub = () => null;
          target[prop] = stub;
          return stub;
        }
        return undefined;
      },
    });
  };

  const attachListeners = (target) => {
    target._listeners = target._listeners ?? [];
    target.addEventListener = function addEventListener(type, fn) {
      this._listeners.push({ type, fn });
    };
    target.removeEventListener = function removeEventListener(type, fn) {
      this._listeners = (this._listeners ?? []).filter((l) => l.fn !== fn);
    };
    target.dispatchEvent = function dispatchEvent(event) {
      const type = event?.type;
      for (const { type: t, fn } of this._listeners ?? []) {
        if (t === type) fn(event);
      }
      return true;
    };
    return target;
  };

  const makeElement = (tag) => {
    const el = attachListeners({
      tagName: String(tag).toUpperCase(),
      nodeType: 1,
      className: "",
      childNodes: [],
      firstElementChild: null,
      parentNode: null,
      style: {},
      _attrs: {},
      width: 0,
      height: 0,
      setAttribute(name, value) {
        this._attrs[name] = value;
        if (name === "href") this.href = value;
        if (name === "style") this.style.cssText = value;
        if (name === "width") this.width = Number(value) || 0;
        if (name === "height") this.height = Number(value) || 0;
      },
      getAttribute(name) {
        return this._attrs[name] ?? null;
      },
      appendChild(child) {
        this.childNodes.push(child);
        child.parentNode = this;
        if (child.nodeType === 1 && !this.firstElementChild) this.firstElementChild = child;
        return child;
      },
      replaceChildren(...kids) {
        this.childNodes = [];
        this.firstElementChild = null;
        for (const child of kids) if (child) this.appendChild(child);
      },
      replaceWith() {},
      remove() {},
      getContext(type) {
        if (String(type).includes("webgl")) {
          webglStats.getContext += 1;
          return makeWebGl();
        }
        return null;
      },
      get textContent() {
        return this.childNodes.map((n) => n.textContent ?? "").join("");
      },
      set textContent(value) {
        this.childNodes = [{ nodeType: 3, textContent: value, childNodes: [] }];
      },
    });
    return el;
  };

  globalThis.Node = { TEXT_NODE: 3, ELEMENT_NODE: 1, DOCUMENT_FRAGMENT_NODE: 11 };
  globalThis.document = attachListeners({
    title: "",
    body: makeElement("body"),
    getElementById(id) {
      if (id === "app") return this._appRoot ?? null;
      return null;
    },
    createElement: (tag) => makeElement(tag),
    createElementNS: (_ns, tag) => makeElement(tag),
    createTextNode: (text) => ({ nodeType: 3, textContent: text, childNodes: [] }),
    createDocumentFragment: () => ({
      nodeType: 11,
      childNodes: [],
      appendChild(child) {
        this.childNodes.push(child);
      },
    }),
  });
  document._appRoot = makeElement("div");
  document._appRoot.id = "app";
  document.body.appendChild(document._appRoot);

  globalThis.window = attachListeners({
    location: {
      protocol: "http:",
      hostname: "localhost",
      port: "",
      pathname: "/wasm",
      search: "",
      hash: "",
      href: "http://localhost/wasm",
      origin: "http://localhost",
    },
    history: {
      pushState() {},
      replaceState() {},
      back() {},
      forward() {},
    },
    scroll() {},
    innerWidth: 1280,
    innerHeight: 720,
    // Don't fire Time.every during the probe — Tick floods update and hangs Node.
    setInterval() {
      return 1;
    },
    clearInterval() {},
    // WebGL.toHtml schedules drawGL via requestAnimationFrame. Run callbacks
    // synchronously so the Node probe observes draws before exit.
    requestAnimationFrame(cb) {
      if (typeof cb === "function") cb(0);
      return 1;
    },
    cancelAnimationFrame() {},
  });
  globalThis.setInterval = window.setInterval;
  globalThis.clearInterval = window.clearInterval;
  globalThis.requestAnimationFrame = window.requestAnimationFrame;
  globalThis.cancelAnimationFrame = window.cancelAnimationFrame;

  return webglStats;
}

function countListeners(target, type) {
  return (target?._listeners ?? []).filter((l) => l.type === type).length;
}

function findEventTarget(node, eventName, out = [], depth = 0) {
  if (!node || depth > 12) return out;
  if ((node._listeners ?? []).some((l) => l.type === eventName)) out.push(node);
  for (const child of node.childNodes ?? []) findEventTarget(child, eventName, out, depth + 1);
  return out;
}

function countCanvases(node, out = [], depth = 0) {
  if (!node || depth > 14) return out;
  if (String(node.tagName || "").toLowerCase() === "canvas") out.push(node);
  for (const child of node.childNodes ?? []) countCanvases(child, out, depth + 1);
  return out;
}

const webglStats = installDomStubs();

console.error("[hero-probe] start");

const { helpers, callExport } = await loadWasmFromBuildDir(buildDir);
console.error("[hero-probe] wasm loaded");
const routeBytes = new Uint8Array(readFileSync(routeBytesPath));
helpers.registerRouteBytes?.("/wasm", routeBytes);

const { rc, value: programHandle } = callExport("elmc_fn_Main_main", []);
console.error(`[hero-probe] main rc=${rc}`);
if (rc !== RC_SUCCESS) {
  console.error(`main failed: rc=${rc}`);
  process.exit(1);
}

const bytesHandle = helpers.newBytesFromUint8Array(routeBytes);

try {
  console.error("[hero-probe] boot begin");
  const boot = helpers.bootBrowserProgram(programHandle, {
    incomingPorts: { pageDataFromJs: bytesHandle },
    skipInnerText: true,
  });
  if (boot.rc !== RC_SUCCESS) {
    console.error(`boot failed: rc=${boot.rc} stage=${boot.stage}`);
    process.exit(1);
  }

  const canvases = countCanvases(document._appRoot);
  const webglInfo = globalThis.__ELMC_WEBGL_TOHTML__ ?? {};
  const entities = webglInfo.count ?? webglInfo.entities ?? 0;
  const draws = (webglStats.drawElements | 0) + (webglStats.drawArrays | 0);
  console.error("[hero-probe] boot", {
    rc: boot.rc,
    stage: boot.stage,
    title: boot.title,
    bodyKids: document._appRoot?.childNodes?.length,
    webgl: webglInfo,
    clear: webglStats.clear,
  });
  console.log(
    `[hero-probe] ok entities=${entities} draws=${draws} canvases=${canvases.length}`
  );

  if (entities < 1) {
    console.error(`hero probe: expected WebGL entities >= 1, got ${entities}`);
    process.exit(1);
  }
  if (draws < 1) {
    console.error(`hero probe: expected WebGL draws >= 1, got ${draws}`);
    process.exit(1);
  }
  if (canvases.length < 1) {
    console.error(`hero probe: expected canvas >= 1, got ${canvases.length}`);
    process.exit(1);
  }

  const downTargets = findEventTarget(document._appRoot, "mousedown");

  if (downTargets.length < 1) {
    console.error("hero probe: expected mousedown listener on the scene");
    process.exit(1);
  }

  const moveBefore = countListeners(document, "mousemove");
  downTargets[0].dispatchEvent({ type: "mousedown", button: 0 });
  const moveAfter = countListeners(document, "mousemove");
  console.error(`[hero-probe] mousemove listeners before=${moveBefore} after=${moveAfter}`);

  if (moveAfter <= moveBefore) {
    console.error(
      `hero probe: expected document mousemove after mousedown (before=${moveBefore} after=${moveAfter})`
    );
    process.exit(1);
  }
  document.dispatchEvent({
    type: "mousemove",
    movementX: 12,
    movementY: -4,
  });
  console.log("[hero-probe] orbit ok");
  process.exit(0);
} catch (err) {
  console.error("boot threw:", err && err.stack ? err.stack : err);
  process.exit(1);
}
