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
import {LiveSocket, type ViewHook} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import {EmbeddedEmulatorHost} from "./emulator/embedded_emulator"
import {WasmEmulatorHost} from "./emulator/wasm_emulator"
import {CodeMirrorEditorHost} from "./editor/codemirror_editor_host"
import type {SimulatorSettings} from "./types/emulator"
import type {FirebaseNamespace} from "./types/window"
import type {HookContext} from "./types/liveview_hook"
import {errMessage} from "./types/errors"

type JsonResponse = Record<string, unknown> & {
  error?: string
  redirect_to?: string
  id_token?: string
}

type FirebaseConfig = Record<string, unknown>

type IdeTheme = "dark" | "light" | "system"

type FirebaseAuthRefreshContext = HookContext & {
  onAuthRefreshed?: (event: CustomEvent<{id_token?: string}>) => void
}

type TokenEditorContext = HookContext & {
  editorHost?: CodeMirrorEditorHost
}

type EditorDocsResizerContext = HookContext & {
  section: HTMLElement | null
  dragging: boolean
  startX: number
  startW: number
  lastW: number
  min: number
  max: number
  applyGrid: (w: number) => void
  readAttrs: () => void
  onMove: (e: MouseEvent) => void
  onUp: () => void
  onDown: (e: MouseEvent) => void
}

type DebuggerShortcutsContext = HookContext & {
  onWindowKeydown: (event: KeyboardEvent) => void
}

type PreserveRenderedDetailsContext = HookContext & {
  openByPath: Record<string, boolean>
  boundDetails: WeakSet<HTMLDetailsElement>
  hoveredPath: string | null
  hoveredScope: string | null
  onToggle: (event: Event) => void
  onMouseOver: (event: MouseEvent) => void
  onMouseOut: (event: MouseEvent) => void
  syncDetails: () => void
}

type WatchAccelPadContext = HookContext & {
  mode: string
  dragging: boolean
  lastSentAt: number
  svg: SVGSVGElement | null
  cross: SVGGraphicsElement | null
  readout: HTMLElement | null
  onPointerDown: (event: PointerEvent) => void
  onPointerMove: (event: PointerEvent) => void
  onPointerUp: (event: PointerEvent) => void
  updateFromEvent: (event: PointerEvent, forceSend: boolean) => void
  sendSample: (x: number, y: number, z: number) => void
}

type AutoDismissFlashContext = HookContext & {
  dismissTimer: ReturnType<typeof setTimeout> | null
  clearTimer: () => void
  scheduleDismiss: () => void
}

type VectorSequenceAnimClock = {
  startedAt: number
}

type VectorSequenceAnimationContext = HookContext & {
  frames: HTMLElement[]
  durations: number[]
  playCount: number
  frameIndex: number
  timer: ReturnType<typeof setInterval> | null
  showFrame: (index: number) => void
  syncFrame: () => void
  readConfig: () => void
}

const debuggerVectorSequenceAnimState: Map<string, VectorSequenceAnimClock> =
  (window as unknown as {__debuggerVectorSequenceAnimState?: Map<string, VectorSequenceAnimClock>})
    .__debuggerVectorSequenceAnimState ??
  (() => {
    const map = new Map<string, VectorSequenceAnimClock>()
    ;(window as unknown as {__debuggerVectorSequenceAnimState: Map<string, VectorSequenceAnimClock>}).__debuggerVectorSequenceAnimState =
      map
    return map
  })()

function vectorSequenceInfinitePlayCount(playCount: number): boolean {
  return playCount === 0 || playCount === 0xffff || playCount === 0xffffffff
}

function vectorSequenceFrameIndexAtElapsed(
  elapsedMs: number,
  durations: number[],
  playCount: number
): number {
  if (durations.length === 0) return 0

  const totalMs = durations.reduce((sum, duration) => sum + (duration > 0 ? duration : 1), 0)
  if (totalMs <= 0) return 0

  let windowMs = elapsedMs
  if (!vectorSequenceInfinitePlayCount(playCount)) {
    const limit = totalMs * Math.max(playCount, 1)
    if (windowMs >= limit) return durations.length - 1
  }

  windowMs = windowMs % totalMs

  let acc = 0
  for (let index = 0; index < durations.length; index++) {
    const duration = durations[index] ?? 1
    acc += duration > 0 ? duration : 1
    if (windowMs < acc) return index
  }

  return durations.length - 1
}

type CopyToClipboardContext = HookContext & {
  defaultLabel: string | null
  resetTimer: ReturnType<typeof setTimeout> | null
  onClick: () => Promise<void>
  showCopied: () => void
  copyText: () => string
  fallbackCopy: (text: string) => void
}

type EmbeddedEmulatorContext = HookContext & {
  host?: EmbeddedEmulatorHost
}

type WasmEmulatorContext = HookContext & {
  host?: WasmEmulatorHost
}

const firebaseScriptUrls = [
  "https://www.gstatic.com/firebasejs/8.10.1/firebase-app.js",
  "https://www.gstatic.com/firebasejs/8.10.1/firebase-auth.js"
]

let firebaseLoadPromise: Promise<FirebaseNamespace> | null = null

function authCsrfToken(): string | null {
  const meta = document.querySelector("meta[name='csrf-token']")
  return meta?.getAttribute("content") ?? null
}

function postJson(url: string, body?: Record<string, unknown>): Promise<JsonResponse> {
  return fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-csrf-token": authCsrfToken() || ""
    },
    body: JSON.stringify(body || {})
  }).then(async response => {
    const data = (await response.json().catch(() => ({}))) as JsonResponse
    if (!response.ok) throw new Error(data.error || `Request failed (${response.status})`)
    return data
  })
}

function loadScript(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const existing = document.querySelector(`script[src="${src}"]`)
    if (existing instanceof HTMLScriptElement) {
      existing.addEventListener("load", () => resolve(), {once: true})
      existing.addEventListener("error", reject, {once: true})
      if (existing.dataset.loaded === "true") resolve()
      return
    }

    const script = document.createElement("script")
    script.src = src
    script.async = true
    script.onload = () => {
      script.dataset.loaded = "true"
      resolve()
    }
    script.onerror = reject
    document.head.appendChild(script)
  })
}

function loadFirebase(config: FirebaseConfig): Promise<FirebaseNamespace> {
  if (!firebaseLoadPromise) {
    firebaseLoadPromise = firebaseScriptUrls
      .reduce<Promise<void>>((promise, src) => promise.then(() => loadScript(src)), Promise.resolve())
      .then(() => {
        const firebase = window.firebase
        if (!firebase) throw new Error("Firebase failed to load")
        if (!firebase.apps.length) firebase.initializeApp(config)
        return firebase
      })
  }

  return firebaseLoadPromise
}

function firebaseProvider(firebase: FirebaseNamespace, providerName: string): unknown {
  if (providerName === "github") return new firebase.auth.GithubAuthProvider()
  if (providerName === "apple") return new firebase.auth.OAuthProvider("apple.com")
  return new firebase.auth.GoogleAuthProvider()
}

async function firebaseLogin(config: FirebaseConfig, providerName: string): Promise<JsonResponse> {
  const firebase = await loadFirebase(config)
  const result = await firebase.auth().signInWithPopup(firebaseProvider(firebase, providerName))
  const idToken = await result.user.getIdToken()
  const data = await postJson("/auth/firebase", {id_token: idToken})
  return {...data, id_token: idToken}
}

async function firebaseLogout(config: FirebaseConfig): Promise<JsonResponse> {
  const firebase = await loadFirebase(config)
  await firebase.auth().signOut()
  return postJson("/auth/logout", {})
}

function authConfigFromElement(el: Element | null): FirebaseConfig | null {
  const host =
    (el?.closest?.("[data-firebase-config]") as HTMLElement | null) ||
    document.querySelector<HTMLElement>("[data-firebase-config]")

  const raw = host?.dataset.firebaseConfig
  if (!raw) return null
  return JSON.parse(raw) as FirebaseConfig
}

document.addEventListener("submit", event => {
  const form = event.target
  if (!(form instanceof HTMLFormElement) || !form.matches("[data-submit-once]")) return

  if (form.dataset.submitting === "true") {
    event.preventDefault()
    return
  }

  form.dataset.submitting = "true"

  const button = form.querySelector("button[type='submit']")
  if (button instanceof HTMLButtonElement) {
    button.disabled = true
    const disableWith = button.dataset.disableWith
    if (disableWith) button.textContent = disableWith
  }
})

document.addEventListener("click", async event => {
  const target = event.target
  if (!(target instanceof Element)) return

  const loginButton = target.closest<HTMLElement>(".firebase-login")
  const sessionLogoutButton = target.closest<HTMLElement>(".ide-session-logout")
  const logoutButton = target.closest<HTMLElement>(".firebase-logout")
  if (!loginButton && !logoutButton && !sessionLogoutButton) return

  event.preventDefault()
  const button = loginButton || logoutButton || sessionLogoutButton
  if (!button) return

  const config = authConfigFromElement(button.closest("[data-firebase-config]") || document.body)
  const status = document.getElementById("firebase-login-status")

  if (loginButton && !config) {
    if (status) status.textContent = "Firebase configuration is missing."
    return
  }

  if ("disabled" in button) button.disabled = true
  if (status) status.textContent = loginButton ? "Opening login..." : "Logging out..."

  try {
    if (loginButton) {
      const data = await firebaseLogin(config!, loginButton.dataset.provider || "google")
      if (status) status.textContent = "Logged in."
      if (loginButton.dataset.liveAuth === "true") {
        window.dispatchEvent(new CustomEvent("elm-pebble-auth-refreshed", {detail: data}))
        if ("disabled" in button) button.disabled = false
      } else {
        window.location.href = loginButton.dataset.returnTo || data.redirect_to || window.location.href
      }
    } else if (sessionLogoutButton) {
      await postJson("/auth/logout", {})
      window.location.href = "/login"
    } else {
      if (config) {
        try {
          await firebaseLogout(config)
        } catch (_error) {}
      }

      await postJson("/auth/logout", {})
      window.location.href = "/login"
    }
  } catch (error) {
    if (status) status.textContent = errMessage(error)
    if ("disabled" in button) button.disabled = false
  }
})

async function refreshFirebaseIdToken(
  config: FirebaseConfig,
  providerName?: string
): Promise<{id_token?: string}> {
  const firebase = await loadFirebase(config)
  const user = firebase.auth().currentUser

  if (user) {
    const idToken = await user.getIdToken(true)
    return {id_token: idToken}
  }

  return firebaseLogin(config, providerName || "google")
}

const FirebaseAuthRefresh: ViewHook = {
  mounted(this: FirebaseAuthRefreshContext) {
    this.onAuthRefreshed = event => {
      const detail = event.detail || {}
      if (detail.id_token) this.pushEvent("firebase-auth-refreshed", {id_token: detail.id_token})
    }

    window.addEventListener("elm-pebble-auth-refreshed", this.onAuthRefreshed)

    this.handleEvent("request-firebase-auth-refresh", async payload => {
      const config = authConfigFromElement(this.el)
      const provider =
        payload && typeof payload === "object" && "provider" in payload
          ? String((payload as {provider?: unknown}).provider ?? "")
          : undefined

      if (!config) {
        this.pushEvent("firebase-auth-refresh-failed", {
          error: "Firebase configuration is missing."
        })
        return
      }

      try {
        const data = await refreshFirebaseIdToken(config, provider)
        if (data.id_token) {
          this.pushEvent("firebase-auth-refreshed", {id_token: data.id_token})
        } else {
          this.pushEvent("firebase-auth-refresh-failed", {error: "No App Store login token returned."})
        }
      } catch (error) {
        this.pushEvent("firebase-auth-refresh-failed", {
          error: errMessage(error)
        })
      }
    })
  },

  destroyed(this: FirebaseAuthRefreshContext) {
    if (this.onAuthRefreshed) {
      window.removeEventListener("elm-pebble-auth-refreshed", this.onAuthRefreshed)
    }
  }
}

function applyIdeTheme(theme: string | undefined) {
  const normalized: IdeTheme = theme === "dark" || theme === "light" ? theme : "system"
  document.body.dataset.ideTheme = normalized
}

applyIdeTheme(document.body.dataset.ideTheme)
window.addEventListener("phx:ide-theme-changed", event => applyIdeTheme(event.detail?.theme))

const isTypingTarget = (target: EventTarget | null): target is HTMLElement => {
  const candidates: HTMLElement[] = []

  if (target instanceof HTMLElement) candidates.push(target)
  if (document.activeElement instanceof HTMLElement) candidates.push(document.activeElement)

  return candidates.some(
    node =>
      node.tagName === "INPUT" ||
      node.tagName === "TEXTAREA" ||
      node.isContentEditable ||
      node.closest(".cm-editor") != null
  )
}

let loadCodeMirrorHostPromise: Promise<typeof CodeMirrorEditorHost> | null = null

function loadCodeMirrorHost(): Promise<typeof CodeMirrorEditorHost> {
  if (!loadCodeMirrorHostPromise) {
    loadCodeMirrorHostPromise = import("./editor/codemirror_editor_host").then(
      module => module.CodeMirrorEditorHost
    )
  }

  return loadCodeMirrorHostPromise
}

const TokenEditor: ViewHook = {
  async mounted(this: TokenEditorContext) {
    const CodeMirrorEditorHostClass = await loadCodeMirrorHost()
    if (this.destroyedBeforeReady) return

    this.editorHost = new CodeMirrorEditorHostClass(this)
    this.handleEvent("token-editor-focus", payload =>
      this.editorHost?.focusPosition(payload as Parameters<CodeMirrorEditorHost["focusPosition"]>[0])
    )
    this.handleEvent("token-editor-restore-state", payload =>
      this.editorHost?.restoreState(payload as Parameters<CodeMirrorEditorHost["restoreState"]>[0])
    )
    this.handleEvent("token-editor-apply-edit", payload =>
      this.editorHost?.applyServerEdit(payload as Parameters<CodeMirrorEditorHost["applyServerEdit"]>[0])
    )
    this.handleEvent("token-editor-token-highlights", payload =>
      this.editorHost?.applyTokenHighlights(
        payload as Parameters<CodeMirrorEditorHost["applyTokenHighlights"]>[0]
      )
    )
    this.handleEvent("token-editor-fold-ranges", payload =>
      this.editorHost?.applyFoldRanges(payload as Parameters<CodeMirrorEditorHost["applyFoldRanges"]>[0])
    )
    this.handleEvent("token-editor-lint-diagnostics", payload =>
      this.editorHost?.applyLintDiagnostics(
        payload as Parameters<CodeMirrorEditorHost["applyLintDiagnostics"]>[0]
      )
    )
    this.handleEvent("token-editor-context-action", payload => {
      const action = typeof payload?.action === "string" ? payload.action : ""
      if (action) this.editorHost?.runContextAction(action)
    })
    this.editorHost.mount()
  },

  updated(this: TokenEditorContext) {
    this.editorHost?.updated()
  },

  destroyed(this: TokenEditorContext) {
    this.destroyedBeforeReady = true
    this.editorHost?.destroy()
  }
}

const EditorDocsResizer: ViewHook = {
  mounted(this: EditorDocsResizerContext) {
    this.section = this.el.closest("section")
    this.dragging = false
    this.startX = 0
    this.startW = 352
    this.lastW = 352
    this.min = 200
    this.max = 720

    this.applyGrid = w => {
      if (!this.section) return
      this.section.style.gridTemplateColumns = `16rem minmax(0, 1fr) 6px ${w}px`
    }

    this.readAttrs = () => {
      this.min = parseInt(this.el.dataset.min || "200", 10)
      this.max = parseInt(this.el.dataset.max || "720", 10)
      this.startW = parseInt(this.el.dataset.width || "352", 10)
    }

    this.onMove = e => {
      if (!this.dragging) return
      const delta = e.clientX - this.startX
      this.lastW = Math.min(this.max, Math.max(this.min, this.startW - delta))
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

    this.onDown = e => {
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

  updated(this: EditorDocsResizerContext) {
    this.section = this.el.closest("section")
    this.readAttrs()
    this.applyGrid(this.startW)
  },

  destroyed(this: EditorDocsResizerContext) {
    this.el.removeEventListener("mousedown", this.onDown)
    window.removeEventListener("mousemove", this.onMove)
    window.removeEventListener("mouseup", this.onUp)
    document.body.style.userSelect = ""
  }
}

const DebuggerShortcuts: ViewHook = {
  mounted(this: DebuggerShortcutsContext) {
    this.onWindowKeydown = event => {
      const pane = this.el.dataset.pane
      if (pane !== "debugger") return

      if (isTypingTarget(event.target)) return

      if (event.key === "/") {
        event.preventDefault()
        const searchInput = document.getElementById("debugger-timeline-search")
        if (searchInput instanceof HTMLElement) searchInput.focus()
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

  destroyed(this: DebuggerShortcutsContext) {
    window.removeEventListener("keydown", this.onWindowKeydown)
  }
}

const PreserveRenderedDetails: ViewHook = {
  mounted(this: PreserveRenderedDetailsContext) {
    this.openByPath = {}
    this.boundDetails = new WeakSet()
    this.hoveredPath = null
    this.hoveredScope = null
    this.onToggle = event => {
      const details = event.currentTarget
      if (!(details instanceof HTMLDetailsElement)) return
      const path = details.dataset.renderedNodePath
      if (!path) return
      this.openByPath[path] = details.open
    }
    this.onMouseOver = event => {
      const hoverTarget = event.target instanceof Element
        ? event.target.closest<HTMLElement>("[data-rendered-node-hover-path]")
        : null
      if (!hoverTarget || !this.el.contains(hoverTarget)) return

      const path = hoverTarget.dataset.renderedNodeHoverPath
      const scope = hoverTarget.dataset.renderedNodeHoverScope
      if (!path || !scope) return
      if (path === this.hoveredPath && scope === this.hoveredScope) return

      this.hoveredPath = path
      this.hoveredScope = scope
      this.pushEvent("debugger-hover-rendered-node", {path, scope})
    }
    this.onMouseOut = event => {
      const hoverTarget = event.target instanceof Element
        ? event.target.closest<HTMLElement>("[data-rendered-node-hover-path]")
        : null
      if (!hoverTarget || !this.el.contains(hoverTarget)) return
      if (event.relatedTarget instanceof Node && hoverTarget.contains(event.relatedTarget)) return

      this.hoveredPath = null
      this.hoveredScope = null
      this.pushEvent("debugger-clear-rendered-node-hover", {})
    }

    this.syncDetails = () => {
      this.el.querySelectorAll("details[data-rendered-node-path]").forEach(details => {
        if (!(details instanceof HTMLDetailsElement)) return
        const path = details.dataset.renderedNodePath
        if (!path) return

        if (Object.prototype.hasOwnProperty.call(this.openByPath, path)) {
          details.open = this.openByPath[path] ?? false
        }

        if (!this.boundDetails.has(details)) {
          details.addEventListener("toggle", this.onToggle)
          this.boundDetails.add(details)
        }
      })
    }

    this.syncDetails()
    this.el.addEventListener("mouseover", this.onMouseOver)
    this.el.addEventListener("mouseout", this.onMouseOut)
  },

  updated(this: PreserveRenderedDetailsContext) {
    this.syncDetails()
  },

  destroyed(this: PreserveRenderedDetailsContext) {
    this.el.querySelectorAll("details[data-rendered-node-path]").forEach(details => {
      if (details instanceof HTMLDetailsElement) {
        details.removeEventListener("toggle", this.onToggle)
      }
    })
    this.el.removeEventListener("mouseover", this.onMouseOver)
    this.el.removeEventListener("mouseout", this.onMouseOut)
  }
}

const WatchAccelPad: ViewHook = {
  mounted(this: WatchAccelPadContext) {
    this.mode = this.el.dataset.mode || "debugger"
    this.dragging = false
    this.lastSentAt = 0
    this.svg = this.el.querySelector("svg")
    this.cross = this.el.querySelector("[data-accel-cross]")
    this.readout = this.el.closest("[data-copy-scope]")?.querySelector<HTMLElement>("[data-accel-readout]") ?? null

    this.updateFromEvent = (event, forceSend) => {
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
      const x = Math.round((dx / radius) * 1000)
      const y = Math.round((-dy / radius) * 1000)
      const z = Math.round(Math.sqrt(Math.max(0, 1_000_000 - x * x - y * y)))

      this.cross?.setAttribute("transform", `translate(${60 + dx} ${60 + dy})`)
      if (this.readout) this.readout.textContent = `x ${x} · y ${y} · z ${z}`

      const now = Date.now()
      if (!forceSend && now - this.lastSentAt < 80) return
      this.lastSentAt = now

      this.sendSample(x, y, z)
    }

    this.sendSample = (x, y, z) => {
      if (this.mode === "emulator") {
        const emulatorEl = this.el.closest('[phx-hook="EmbeddedEmulator"]')
        if (emulatorEl instanceof HTMLElement && emulatorEl.__embeddedEmulatorHost?.sendAccelSample) {
          emulatorEl.__embeddedEmulatorHost.sendAccelSample(x, y, z)
        }
        return
      }

      this.pushEvent("debugger-inject-trigger", {
        trigger: this.el.dataset.trigger || "on_accel_data",
        target: this.el.dataset.target || "watch",
        message: this.el.dataset.message,
        message_value: {x, y, z}
      })
    }

    this.onPointerDown = event => {
      if (this.el.dataset.disabled === "true") return
      this.dragging = true
      this.svg?.setPointerCapture(event.pointerId)
      this.updateFromEvent(event, true)
    }

    this.onPointerMove = event => {
      if (!this.dragging) return
      this.updateFromEvent(event, false)
    }

    this.onPointerUp = event => {
      if (!this.dragging) return
      this.dragging = false
      this.updateFromEvent(event, true)
      this.svg?.releasePointerCapture(event.pointerId)
    }

    this.svg?.addEventListener("pointerdown", this.onPointerDown)
    this.svg?.addEventListener("pointermove", this.onPointerMove)
    this.svg?.addEventListener("pointerup", this.onPointerUp)
    this.svg?.addEventListener("pointercancel", this.onPointerUp)
  },

  destroyed(this: WatchAccelPadContext) {
    this.svg?.removeEventListener("pointerdown", this.onPointerDown)
    this.svg?.removeEventListener("pointermove", this.onPointerMove)
    this.svg?.removeEventListener("pointerup", this.onPointerUp)
    this.svg?.removeEventListener("pointercancel", this.onPointerUp)
  }
}

const DebuggerAccelPad = WatchAccelPad

const AutoDismissFlash: ViewHook = {
  mounted(this: AutoDismissFlashContext) {
    this.dismissTimer = null
    this.clearTimer = () => {
      if (this.dismissTimer != null) {
        window.clearTimeout(this.dismissTimer)
        this.dismissTimer = null
      }
    }
    this.scheduleDismiss = () => {
      this.clearTimer()

      const flashKey = this.el.dataset.flashKey
      const dismissMs = parseInt(this.el.dataset.autoDismissMs || "2500", 10)
      if (!flashKey || !Number.isFinite(dismissMs) || dismissMs < 0) return

      this.dismissTimer = window.setTimeout(() => {
        this.pushEvent("lv:clear-flash", {key: flashKey})
        this.el.style.display = "none"
      }, dismissMs)
    }
    this.scheduleDismiss()
  },

  updated(this: AutoDismissFlashContext) {
    this.scheduleDismiss()
  },

  destroyed(this: AutoDismissFlashContext) {
    this.clearTimer()
  }
}

const VectorSequenceAnimation: ViewHook = {
  mounted(this: VectorSequenceAnimationContext) {
    this.frames = [...this.el.querySelectorAll<HTMLElement>(".debugger-vector-seq-frame")]
    this.frameIndex = -1
    this.timer = null

    this.showFrame = index => {
      if (index === this.frameIndex) return
      this.frames.forEach((frame, frameIndex) => {
        frame.style.opacity = frameIndex === index ? "1" : "0"
      })
      this.frameIndex = index
    }

    this.readConfig = () => {
      this.durations = JSON.parse(this.el.dataset.frameDurations || "[]") as number[]
      this.playCount = Number.parseInt(this.el.dataset.playCount || "1", 10)
    }

    this.syncFrame = () => {
      if (this.frames.length <= 1) {
        this.showFrame(0)
        return
      }

      const animId = this.el.id
      if (!animId) return

      let clock = debuggerVectorSequenceAnimState.get(animId)
      if (!clock) {
        clock = {startedAt: performance.now()}
        debuggerVectorSequenceAnimState.set(animId, clock)
      }

      const index = vectorSequenceFrameIndexAtElapsed(
        performance.now() - clock.startedAt,
        this.durations,
        this.playCount
      )
      this.showFrame(index)
    }

    this.readConfig()
    this.syncFrame()

    if (this.frames.length > 1) {
      this.timer = window.setInterval(() => this.syncFrame(), 33)
    }
  },

  updated(this: VectorSequenceAnimationContext) {
    this.readConfig()
    this.syncFrame()
  },

  destroyed(this: VectorSequenceAnimationContext) {
    if (this.timer != null) window.clearInterval(this.timer)
  }
}

const CopyToClipboard: ViewHook = {
  mounted(this: CopyToClipboardContext) {
    this.defaultLabel = this.el.textContent
    this.resetTimer = null

    this.showCopied = () => {
      this.el.textContent = "Copied"
      if (this.resetTimer != null) window.clearTimeout(this.resetTimer)
      this.resetTimer = window.setTimeout(() => {
        this.el.textContent = this.defaultLabel
      }, 1500)
    }

    this.copyText = () => {
      const selector = this.el.dataset.copySelector
      if (!selector) return this.el.dataset.copyText || ""

      const scope = this.el.closest("[data-copy-scope]") || document
      const target = scope.querySelector(selector) || document.querySelector(selector)
      if (!(target instanceof Element)) return ""

      if (target.namespaceURI === "http://www.w3.org/2000/svg") {
        const clone = target.cloneNode(true)
        if (clone instanceof Element) {
          clone.setAttribute("xmlns", "http://www.w3.org/2000/svg")
          return clone.outerHTML
        }
        return ""
      }

      return target.outerHTML || target.textContent || ""
    }

    this.fallbackCopy = text => {
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

  destroyed(this: CopyToClipboardContext) {
    this.el.removeEventListener("click", this.onClick)
    if (this.resetTimer != null) window.clearTimeout(this.resetTimer)
  }
}

const EmbeddedEmulator: ViewHook = {
  mounted(this: EmbeddedEmulatorContext) {
    this.host = new EmbeddedEmulatorHost(this)
    this.el.__embeddedEmulatorHost = this.host
    this.host.mount()
  },

  updated(this: EmbeddedEmulatorContext) {
    this.host?.updated()
  },

  handleEvent(this: EmbeddedEmulatorContext, event: string, payload: unknown) {
    if (this.host && event === "simulator_settings_applied") {
      this.host.applySimulatorSettings(payload as SimulatorSettings, {source: "push_event", quiet: false})
    }
  },

  destroyed(this: EmbeddedEmulatorContext) {
    delete this.el.__embeddedEmulatorHost
    this.host?.destroy()
  }
}

const WasmEmulator: ViewHook = {
  mounted(this: WasmEmulatorContext) {
    this.host = new WasmEmulatorHost(this)
    this.host.mount()
  },

  updated(this: WasmEmulatorContext) {
    this.host?.updated()
  },

  destroyed(this: WasmEmulatorContext) {
    this.host?.destroy()
  }
}

const Hooks = {
  FirebaseAuthRefresh,
  TokenEditor,
  EditorDocsResizer,
  DebuggerShortcuts,
  PreserveRenderedDetails,
  WatchAccelPad,
  DebuggerAccelPad,
  AutoDismissFlash,
  VectorSequenceAnimation,
  CopyToClipboard,
  EmbeddedEmulator,
  WasmEmulator
} satisfies Record<string, ViewHook>

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content") ?? ""
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

window.addEventListener("phx:open_url", e => {
  const url = e.detail?.url
  if (url) window.open(url, "_blank", "noopener,noreferrer")
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
