// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import {EmbeddedEmulatorHost} from "./emulator/embedded_emulator"

let Hooks = {}

function applyIdeTheme(theme) {
  const normalized = theme === "dark" || theme === "light" ? theme : "system"
  document.body.dataset.ideTheme = normalized
}

applyIdeTheme(document.body.dataset.ideTheme)
window.addEventListener("phx:ide-theme-changed", event => applyIdeTheme(event.detail && event.detail.theme))

const isTypingTarget = target =>
  target instanceof HTMLElement &&
  (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable)

let loadCodeMirrorHostPromise = null

function loadCodeMirrorHost() {
  if (!loadCodeMirrorHostPromise) {
    loadCodeMirrorHostPromise = import("./editor/codemirror_editor_host").then(
      module => module.CodeMirrorEditorHost
    )
  }

  return loadCodeMirrorHostPromise
}

Hooks.TokenEditor = {
  async mounted() {
    const CodeMirrorEditorHost = await loadCodeMirrorHost()
    if (this.destroyedBeforeReady) return

    this.editorHost = new CodeMirrorEditorHost(this)
    this.handleEvent("token-editor-focus", payload => this.editorHost && this.editorHost.focusPosition(payload))
    this.handleEvent(
      "token-editor-restore-state",
      payload => this.editorHost && this.editorHost.restoreState(payload)
    )
    this.handleEvent(
      "token-editor-apply-edit",
      payload => this.editorHost && this.editorHost.applyServerEdit(payload)
    )
    this.handleEvent(
      "token-editor-show-completions",
      payload => this.editorHost && this.editorHost.showCompletions(payload)
    )
    this.handleEvent(
      "token-editor-token-highlights",
      payload => this.editorHost && this.editorHost.applyTokenHighlights(payload)
    )
    this.handleEvent(
      "token-editor-fold-ranges",
      payload => this.editorHost && this.editorHost.applyFoldRanges(payload)
    )
    this.handleEvent(
      "token-editor-lint-diagnostics",
      payload => this.editorHost && this.editorHost.applyLintDiagnostics(payload)
    )
    this.editorHost.mount()
  },

  updated() {
    if (this.editorHost) this.editorHost.updated()
  },

  destroyed() {
    this.destroyedBeforeReady = true
    if (this.editorHost) this.editorHost.destroy()
  }
}

Hooks.EditorDocsResizer = {
  mounted() {
    this.section = this.el.closest("section")
    this.dragging = false
    this.startX = 0
    this.startW = 352
    this.lastW = 352

    this.applyGrid = (w) => {
      if (!this.section) return
      this.section.style.gridTemplateColumns = `16rem minmax(0, 1fr) 6px ${w}px`
    }

    this.readAttrs = () => {
      this.min = parseInt(this.el.dataset.min || "200", 10)
      this.max = parseInt(this.el.dataset.max || "720", 10)
      this.startW = parseInt(this.el.dataset.width || "352", 10)
    }

    this.onMove = (e) => {
      if (!this.dragging) return
      const delta = e.clientX - this.startX
      this.lastW = Math.min(this.max, Math.max(this.min, this.startW + delta))
      this.applyGrid(this.lastW)
    }

    this.onUp = () => {
      if (!this.dragging) return
      this.dragging = false
      document.body.style.userSelect = ""
      window.removeEventListener("mousemove", this.onMove)
      window.removeEventListener("mouseup", this.onUp)
      this.pushEvent("set-editor-docs-width", {px: this.lastW})
    }

    this.onDown = (e) => {
      e.preventDefault()
      this.readAttrs()
      this.dragging = true
      this.startX = e.clientX
      this.lastW = this.startW
      document.body.style.userSelect = "none"
      window.addEventListener("mousemove", this.onMove)
      window.addEventListener("mouseup", this.onUp)
    }

    this.el.addEventListener("mousedown", this.onDown)
    this.readAttrs()
    this.applyGrid(this.startW)
  },

  updated() {
    this.section = this.el.closest("section")
    this.readAttrs()
    this.applyGrid(this.startW)
  },

  destroyed() {
    this.el.removeEventListener("mousedown", this.onDown)
    window.removeEventListener("mousemove", this.onMove)
    window.removeEventListener("mouseup", this.onUp)
    document.body.style.userSelect = ""
  }
}

Hooks.DebuggerShortcuts = {
  mounted() {
    this.onWindowKeydown = (event) => {
      const pane = this.el.dataset.pane
      if (pane !== "debugger") return

      if (isTypingTarget(event.target)) return

      if (event.key === "/") {
        event.preventDefault()
        const searchInput = document.getElementById("debugger-timeline-search")
        if (searchInput) searchInput.focus()
        return
      }

      if (event.key === "j" || event.key === "k") {
        event.preventDefault()
        this.pushEvent("debugger-keydown", {key: event.key})
      }
    }

    window.addEventListener("keydown", this.onWindowKeydown)
  },

  updated() {},

  destroyed() {
    window.removeEventListener("keydown", this.onWindowKeydown)
  }
}

Hooks.PreserveRenderedDetails = {
  mounted() {
    this.openByPath = {}
    this.boundDetails = new WeakSet()
    this.hoveredPath = null
    this.hoveredScope = null
    this.onToggle = (event) => {
      const details = event.currentTarget
      const path = details && details.dataset && details.dataset.renderedNodePath
      if (!path) return
      this.openByPath[path] = details.open
    }
    this.onMouseOver = (event) => {
      const target = event.target.closest("[data-rendered-node-hover-path]")
      if (!target || !this.el.contains(target)) return

      const path = target.dataset.renderedNodeHoverPath
      const scope = target.dataset.renderedNodeHoverScope
      if (!path || !scope) return
      if (path === this.hoveredPath && scope === this.hoveredScope) return

      this.hoveredPath = path
      this.hoveredScope = scope
      this.pushEvent("debugger-hover-rendered-node", {path, scope})
    }
    this.onMouseOut = (event) => {
      const target = event.target.closest("[data-rendered-node-hover-path]")
      if (!target || !this.el.contains(target)) return
      if (target.contains(event.relatedTarget)) return

      this.hoveredPath = null
      this.hoveredScope = null
      this.pushEvent("debugger-clear-rendered-node-hover", {})
    }

    this.syncDetails()
    this.el.addEventListener("mouseover", this.onMouseOver)
    this.el.addEventListener("mouseout", this.onMouseOut)
  },

  updated() {
    this.syncDetails()
  },

  destroyed() {
    this.el.querySelectorAll("details[data-rendered-node-path]").forEach(details => {
      details.removeEventListener("toggle", this.onToggle)
    })
    this.el.removeEventListener("mouseover", this.onMouseOver)
    this.el.removeEventListener("mouseout", this.onMouseOut)
  },

  syncDetails() {
    this.el.querySelectorAll("details[data-rendered-node-path]").forEach(details => {
      const path = details.dataset.renderedNodePath

      if (Object.prototype.hasOwnProperty.call(this.openByPath, path)) {
        details.open = this.openByPath[path]
      }

      if (!this.boundDetails.has(details)) {
        details.addEventListener("toggle", this.onToggle)
        this.boundDetails.add(details)
      }
    })
  }
}

Hooks.DebuggerAccelPad = {
  mounted() {
    this.dragging = false
    this.lastSentAt = 0
    this.svg = this.el.querySelector("svg")
    this.cross = this.el.querySelector("[data-accel-cross]")
    this.readout = this.el.closest("[data-copy-scope]")?.querySelector("[data-accel-readout]")

    this.onPointerDown = (event) => {
      this.dragging = true
      this.svg?.setPointerCapture?.(event.pointerId)
      this.updateFromEvent(event, true)
    }

    this.onPointerMove = (event) => {
      if (!this.dragging) return
      this.updateFromEvent(event, false)
    }

    this.onPointerUp = (event) => {
      if (!this.dragging) return
      this.dragging = false
      this.updateFromEvent(event, true)
      this.svg?.releasePointerCapture?.(event.pointerId)
    }

    this.svg?.addEventListener("pointerdown", this.onPointerDown)
    this.svg?.addEventListener("pointermove", this.onPointerMove)
    this.svg?.addEventListener("pointerup", this.onPointerUp)
    this.svg?.addEventListener("pointercancel", this.onPointerUp)
  },

  destroyed() {
    this.svg?.removeEventListener("pointerdown", this.onPointerDown)
    this.svg?.removeEventListener("pointermove", this.onPointerMove)
    this.svg?.removeEventListener("pointerup", this.onPointerUp)
    this.svg?.removeEventListener("pointercancel", this.onPointerUp)
  },

  updateFromEvent(event, forceSend) {
    event.preventDefault()
    if (!this.svg) return

    const rect = this.svg.getBoundingClientRect()
    const scale = 120 / Math.max(rect.width || 1, rect.height || 1)
    const rawDx = (event.clientX - rect.left) * scale - 60
    const rawDy = (event.clientY - rect.top) * scale - 60
    const distance = Math.sqrt(rawDx * rawDx + rawDy * rawDy)
    const radius = 50
    const clamp = distance > radius ? radius / distance : 1
    const dx = rawDx * clamp
    const dy = rawDy * clamp
    const x = Math.round(dx / radius * 1000)
    const y = Math.round(-dy / radius * 1000)
    const z = Math.round(Math.sqrt(Math.max(0, 1000000 - x * x - y * y)))

    this.cross?.setAttribute("transform", `translate(${60 + dx} ${60 + dy})`)
    if (this.readout) this.readout.textContent = `x ${x} · y ${y} · z ${z}`

    const now = Date.now()
    if (!forceSend && now - this.lastSentAt < 80) return
    this.lastSentAt = now

    this.pushEvent("debugger-inject-trigger", {
      trigger: this.el.dataset.trigger,
      target: this.el.dataset.target,
      message: this.el.dataset.message,
      message_value: {x, y, z}
    })
  }
}

Hooks.AutoDismissFlash = {
  mounted() {
    this.scheduleDismiss()
  },

  updated() {
    this.scheduleDismiss()
  },

  destroyed() {
    this.clearTimer()
  },

  clearTimer() {
    if (this.dismissTimer) {
      window.clearTimeout(this.dismissTimer)
      this.dismissTimer = null
    }
  },

  scheduleDismiss() {
    this.clearTimer()

    const flashKey = this.el.dataset.flashKey
    const dismissMs = parseInt(this.el.dataset.autoDismissMs || "2500", 10)
    if (!flashKey || !Number.isFinite(dismissMs) || dismissMs < 0) return

    this.dismissTimer = window.setTimeout(() => {
      this.pushEvent("lv:clear-flash", {key: flashKey})
      this.el.style.display = "none"
    }, dismissMs)
  }
}

Hooks.CopyToClipboard = {
  mounted() {
    this.defaultLabel = this.el.textContent

    this.onClick = async () => {
      const text = this.copyText()
      if (!text) return

      try {
        await navigator.clipboard.writeText(text)
        this.showCopied()
      } catch (_error) {
        this.fallbackCopy(text)
      }
    }

    this.el.addEventListener("click", this.onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
    if (this.resetTimer) window.clearTimeout(this.resetTimer)
  },

  showCopied() {
    this.el.textContent = "Copied"
    if (this.resetTimer) window.clearTimeout(this.resetTimer)
    this.resetTimer = window.setTimeout(() => {
      this.el.textContent = this.defaultLabel
    }, 1500)
  },

  copyText() {
    const selector = this.el.dataset.copySelector
    if (!selector) return this.el.dataset.copyText || ""

    const scope = this.el.closest("[data-copy-scope]") || document
    const target = scope.querySelector(selector) || document.querySelector(selector)
    if (!target) return ""

    if (target.namespaceURI === "http://www.w3.org/2000/svg") {
      const clone = target.cloneNode(true)
      clone.setAttribute("xmlns", "http://www.w3.org/2000/svg")
      return clone.outerHTML
    }

    return target.outerHTML || target.textContent || ""
  },

  fallbackCopy(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "")
    textarea.style.position = "fixed"
    textarea.style.opacity = "0"
    document.body.appendChild(textarea)
    textarea.select()

    try {
      document.execCommand("copy")
      this.showCopied()
    } finally {
      document.body.removeChild(textarea)
    }
  }
}

Hooks.EmbeddedEmulator = {
  mounted() {
    this.host = new EmbeddedEmulatorHost(this)
    this.host.mount()
  },

  updated() {
    if (this.host) this.host.updated()
  },

  destroyed() {
    if (this.host) this.host.destroy()
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

window.addEventListener("phx:open_url", e => {
  const url = e.detail && e.detail.url
  if (url) window.open(url, "_blank", "noopener,noreferrer")
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

