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
import {playSpeakerEffect, setSpeakerSampleCatalog, type SpeakerEffectWire, type SpeakerSampleWire} from "./debugger/speaker_audio"

type JsonResponse = Record<string, unknown> & {
  error?: string
  redirect_to?: string
  id_token?: string
}

type FirebaseLoginOptions = {
  liveAuth?: boolean
  returnTo?: string
}

type FirebaseRedirectState = FirebaseLoginOptions & {
  provider?: string
}

const FIREBASE_REDIRECT_STATE_KEY = "elm-pebble-firebase-redirect"
const FIREBASE_PENDING_ID_TOKEN_KEY = "elm-pebble-firebase-pending-id-token"
const FIREBASE_BRIDGE_PENDING_KEY = "elm-pebble-firebase-bridge-pending"
const FIREBASE_BRIDGE_PATH = "/auth/firebase/bridge"
/** Providers that prefer popup; redirect is unreliable on modern browsers (3P cookies). */
const FIREBASE_BRIDGE_FALLBACK_PROVIDERS = new Set(["github", "apple"])

type IdeTheme = "dark" | "light" | "system"

type FirebaseAuthRefreshContext = HookContext & {
  onAuthRefreshed?: (event: CustomEvent<{id_token?: string}>) => void
  onAuthFailed?: (event: CustomEvent<{error?: string}>) => void
  syncFirebaseUserToken?: () => Promise<void>
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
  if (providerName === "github") {
    const provider = new firebase.auth.GithubAuthProvider()
    provider.addScope("read:user")
    provider.addScope("user:email")
    return provider
  }
  if (providerName === "apple") return new firebase.auth.OAuthProvider("apple.com")
  return new firebase.auth.GoogleAuthProvider()
}

function usesFirebaseBridgeFallback(providerName: string): boolean {
  return FIREBASE_BRIDGE_FALLBACK_PROVIDERS.has(providerName)
}

function stashFirebaseRedirectState(providerName: string, options: FirebaseLoginOptions): void {
  sessionStorage.setItem(
    FIREBASE_REDIRECT_STATE_KEY,
    JSON.stringify({
      liveAuth: options.liveAuth ?? false,
      returnTo: options.returnTo ?? window.location.href,
      provider: providerName
    })
  )
}

function peekFirebaseRedirectState(): FirebaseRedirectState | null {
  const raw = sessionStorage.getItem(FIREBASE_REDIRECT_STATE_KEY)
  if (!raw) return null
  try {
    return JSON.parse(raw) as FirebaseRedirectState
  } catch {
    return null
  }
}

function readFirebaseRedirectState(): FirebaseRedirectState | null {
  const state = peekFirebaseRedirectState()
  sessionStorage.removeItem(FIREBASE_REDIRECT_STATE_KEY)
  return state
}

function setFirebaseLoginStatus(text: string) {
  document.querySelectorAll<HTMLElement>(".firebase-login-status").forEach(el => {
    el.textContent = text
  })
}

async function waitForFirebaseUser(
  firebase: FirebaseNamespace,
  timeoutMs = 5000
): Promise<{getIdToken: (force?: boolean) => Promise<string>} | null> {
  const existing = firebase.auth().currentUser
  if (existing) return existing

  return await new Promise(resolve => {
    let settled = false
    let unsub: (() => void) | null = null
    const finish = (user: {getIdToken: (force?: boolean) => Promise<string>} | null) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      try {
        unsub?.()
      } catch {
        // ignore
      }
      resolve(user)
    }

    unsub = firebase.auth().onAuthStateChanged(user => {
      if (user) finish(user)
    })

    const timer = window.setTimeout(() => finish(firebase.auth().currentUser), timeoutMs)
  })
}

async function completeFirebaseRedirect(config: FirebaseConfig): Promise<boolean> {
  // Bridge page owns OAuth completion for GitHub/Apple fallback.
  if (window.location.pathname === FIREBASE_BRIDGE_PATH) return false

  const redirectState = peekFirebaseRedirectState()
  if (!redirectState) return false

  const firebase = await loadFirebase(config)

  try {
    const result = await firebase.auth().getRedirectResult()
    let user = result.user

    if (!user) {
      user = await waitForFirebaseUser(firebase)
    }

    if (!user) {
      readFirebaseRedirectState()
      return false
    }

    const idToken = await user.getIdToken()
    const data = await postJson("/auth/firebase", {id_token: idToken})
    const state = readFirebaseRedirectState() || redirectState

    sessionStorage.setItem(FIREBASE_PENDING_ID_TOKEN_KEY, idToken)
    setFirebaseLoginStatus("Logged in. Returning…")

    const base =
      state?.liveAuth && state.returnTo
        ? state.returnTo
        : typeof data.redirect_to === "string" && data.redirect_to
          ? data.redirect_to
          : state?.returnTo || window.location.href

    window.location.replace(withAuthReloadParam(base))
    return true
  } catch (error) {
    readFirebaseRedirectState()
    const message = errMessage(error)
    setFirebaseLoginStatus(message)
    window.dispatchEvent(
      new CustomEvent("elm-pebble-auth-refresh-failed", {detail: {error: message}})
    )
    return false
  }
}

function toSameOriginPath(url: string, fallback = "/projects"): string {
  try {
    const parsed = new URL(url, window.location.origin)
    if (parsed.origin !== window.location.origin) return fallback
    return parsed.pathname + parsed.search + parsed.hash
  } catch {
    return fallback
  }
}

function bridgeReturnTo(fallback = "/projects"): string {
  const fromQuery = new URLSearchParams(window.location.search).get("return_to")
  const fromDataset = document.getElementById("firebase-oauth-bridge")?.dataset.returnTo
  const candidate = fromQuery || fromDataset || fallback
  return toSameOriginPath(candidate, fallback)
}

async function finishFirebaseSession(
  user: {getIdToken: (force?: boolean) => Promise<string>},
  returnTo: string
): Promise<void> {
  const idToken = await user.getIdToken(true)
  await postJson("/auth/firebase", {id_token: idToken})
  sessionStorage.setItem(FIREBASE_PENDING_ID_TOKEN_KEY, idToken)
  sessionStorage.removeItem(FIREBASE_BRIDGE_PENDING_KEY)
  sessionStorage.removeItem(FIREBASE_REDIRECT_STATE_KEY)
  setFirebaseLoginStatus("Logged in. Returning…")
  window.location.replace(withAuthReloadParam(toSameOriginPath(returnTo)))
}

async function runFirebaseOAuthBridge(config: FirebaseConfig): Promise<void> {
  const params = new URLSearchParams(window.location.search)
  const provider =
    params.get("provider") ||
    document.getElementById("firebase-oauth-bridge")?.dataset.provider ||
    "github"
  const returnTo = bridgeReturnTo()
  const statusEl = document.getElementById("firebase-oauth-bridge-status")
  const continueBtn = document.getElementById("firebase-oauth-continue")
  const setStatus = (text: string) => {
    if (statusEl) statusEl.textContent = text
    setFirebaseLoginStatus(text)
  }

  // Drop stale redirect-pending flags from earlier attempts.
  sessionStorage.removeItem(FIREBASE_BRIDGE_PENDING_KEY)

  const firebase = await loadFirebase(config)

  try {
    const result = await firebase.auth().getRedirectResult()
    if (result.user) {
      await finishFirebaseSession(result.user, returnTo)
      return
    }
  } catch (error) {
    setStatus(errMessage(error))
  }

  const existing = await waitForFirebaseUser(firebase, 1500)
  if (existing) {
    try {
      await finishFirebaseSession(existing, returnTo)
      return
    } catch (error) {
      setStatus(errMessage(error))
    }
  }

  const priorError = params.get("error")
  setStatus(
    priorError
      ? `${priorError} Click below to try again in a popup.`
      : `Click below to continue with ${provider}.`
  )

  const startPopup = async () => {
    if (continueBtn instanceof HTMLButtonElement) continueBtn.disabled = true
    setStatus(`Opening ${provider} login…`)
    try {
      const cred = await firebase.auth().signInWithPopup(firebaseProvider(firebase, provider))
      if (!cred.user) throw new Error("No user returned from login popup.")
      await finishFirebaseSession(cred.user, returnTo)
    } catch (error) {
      setStatus(errMessage(error))
      if (continueBtn instanceof HTMLButtonElement) continueBtn.disabled = false
    }
  }

  if (continueBtn) {
    continueBtn.addEventListener("click", event => {
      event.preventDefault()
      void startPopup()
    })
  }
}

function withAuthReloadParam(url: string): string {
  try {
    const parsed = new URL(url, window.location.origin)
    parsed.searchParams.set("_firebase_auth", String(Date.now()))
    return parsed.pathname + parsed.search + parsed.hash
  } catch {
    const join = url.includes("?") ? "&" : "?"
    return `${url}${join}_firebase_auth=${Date.now()}`
  }
}

function firebasePopupLikelyBroken(): boolean {
  // Editor/debugger/build set COOP+COEP. LiveView patch to Publish keeps those
  // headers on the document, and Firebase popups then fail with a generic
  // "network error" after a white popup. Fresh Publish loads are not isolated.
  return window.crossOriginIsolated === true
}

function bridgeFallbackUrl(providerName: string, returnTo: string, error?: string): string {
  const url = new URL(FIREBASE_BRIDGE_PATH, window.location.origin)
  url.searchParams.set("provider", providerName)
  url.searchParams.set("return_to", toSameOriginPath(returnTo))
  if (error) url.searchParams.set("error", error.slice(0, 300))
  return url.pathname + url.search
}

async function firebaseLogin(
  config: FirebaseConfig,
  providerName: string,
  options: FirebaseLoginOptions = {}
): Promise<JsonResponse> {
  const firebase = await loadFirebase(config)
  const returnTo = options.returnTo || window.location.href

  // If Firebase already has a session (earlier OAuth succeeded in-browser), sync.
  let existing = firebase.auth().currentUser
  if (!existing && usesFirebaseBridgeFallback(providerName)) {
    existing = await waitForFirebaseUser(firebase, 1200)
  }
  if (existing) {
    const idToken = await existing.getIdToken(true)
    const data = await postJson("/auth/firebase", {id_token: idToken})
    return {...data, id_token: idToken}
  }

  // GitHub/Apple: always use the COOP-free bridge page. Publish is often reached
  // via LiveView patch from Editor, which keeps cross-origin isolation and makes
  // Firebase popups fail with a white window + generic network error.
  if (usesFirebaseBridgeFallback(providerName) || firebasePopupLikelyBroken()) {
    window.location.href = bridgeFallbackUrl(providerName, returnTo)
    return {}
  }

  try {
    const result = await firebase.auth().signInWithPopup(firebaseProvider(firebase, providerName))
    const idToken = await result.user.getIdToken()
    const data = await postJson("/auth/firebase", {id_token: idToken})
    return {...data, id_token: idToken}
  } catch (error) {
    if (usesFirebaseBridgeFallback(providerName)) {
      window.location.href = bridgeFallbackUrl(providerName, returnTo, errMessage(error))
      return {}
    }
    throw error
  }
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
  const statusCard = loginButton?.closest(".rounded.border")
  const statusElements = statusCard
    ? Array.from(statusCard.querySelectorAll<HTMLElement>(".firebase-login-status"))
    : [document.getElementById("firebase-login-status")].filter(
        (el): el is HTMLElement => el instanceof HTMLElement
      )

  const setStatus = (text: string) => {
    for (const el of statusElements) el.textContent = text
  }

  if (loginButton && !config) {
    setStatus("Firebase configuration is missing.")
    return
  }

  if ("disabled" in button) button.disabled = true
  setStatus(loginButton ? "Opening login..." : "Logging out...")

  try {
    if (loginButton) {
      const returnTo =
        loginButton.dataset.returnTo ||
        new URLSearchParams(window.location.search).get("return_to") ||
        window.location.href
      const data = await firebaseLogin(config!, loginButton.dataset.provider || "google", {
        liveAuth: loginButton.dataset.liveAuth === "true",
        returnTo
      })
      setStatus("Logged in.")
      if (loginButton.dataset.liveAuth === "true") {
        window.dispatchEvent(new CustomEvent("elm-pebble-auth-refreshed", {detail: data}))
        if ("disabled" in button) button.disabled = false
      } else {
        window.location.href =
          loginButton.dataset.returnTo ||
          (typeof data.redirect_to === "string" && data.redirect_to) ||
          toSameOriginPath(returnTo) ||
          window.location.href
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
    setStatus(errMessage(error))
    if ("disabled" in button) button.disabled = false
  }
})

async function refreshFirebaseIdToken(
  config: FirebaseConfig,
  providerName?: string
): Promise<{id_token?: string}> {
  const provider = providerName || "google"
  const firebase = await loadFirebase(config)
  const user = firebase.auth().currentUser

  if (user) {
    const idToken = await user.getIdToken(true)
    return {id_token: idToken}
  }

  return firebaseLogin(config, provider, {liveAuth: true, returnTo: window.location.href})
}

const FirebaseAuthRefresh: ViewHook = {
  mounted(this: FirebaseAuthRefreshContext) {
    this.syncFirebaseUserToken = async () => {
      const config = authConfigFromElement(this.el)
      if (!config) return

      try {
        const firebase = await loadFirebase(config)
        const user = (await waitForFirebaseUser(firebase, 8000)) as {
          getIdToken: (force?: boolean) => Promise<string>
        } | null
        if (!user) return

        const idToken = await user.getIdToken(true)
        // LiveView event verifies the token and updates assigns + ETS (no session renew).
        sessionStorage.removeItem(FIREBASE_PENDING_ID_TOKEN_KEY)
        this.pushEvent("firebase-auth-refreshed", {id_token: idToken})
        setFirebaseLoginStatus("Logged in.")
      } catch (error) {
        setFirebaseLoginStatus(errMessage(error))
      }
    }

    this.onAuthRefreshed = event => {
      const detail = event.detail || {}
      if (detail.id_token) {
        sessionStorage.removeItem(FIREBASE_PENDING_ID_TOKEN_KEY)
        this.pushEvent("firebase-auth-refreshed", {id_token: detail.id_token})
      }
    }

    window.addEventListener("elm-pebble-auth-refreshed", this.onAuthRefreshed)

    this.onAuthFailed = event => {
      const detail = event.detail || {}
      if (detail.error) this.pushEvent("firebase-auth-refresh-failed", {error: detail.error})
    }

    window.addEventListener("elm-pebble-auth-refresh-failed", this.onAuthFailed)

    const pendingToken = sessionStorage.getItem(FIREBASE_PENDING_ID_TOKEN_KEY)
    if (pendingToken) {
      sessionStorage.removeItem(FIREBASE_PENDING_ID_TOKEN_KEY)
      this.pushEvent("firebase-auth-refreshed", {id_token: pendingToken})
    } else if (document.querySelector(".firebase-login")) {
      // Redirect completion can miss getRedirectResult; Firebase persistence may
      // still have the user while the Publish page still shows login buttons.
      void this.syncFirebaseUserToken()
    }

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
    if (this.onAuthFailed) {
      window.removeEventListener("elm-pebble-auth-refresh-failed", this.onAuthFailed)
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
      const typed = payload as { action?: string }
      const action = typeof typed.action === "string" ? typed.action : ""
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

type DebuggerSpeakerContext = HookContext & {
  lastSeq?: number
}

const DebuggerSpeaker: ViewHook = {
  mounted(this: DebuggerSpeakerContext) {
    this.lastSeq = readSpeakerEffectSeq(this)
    syncSpeakerSampleCatalog(this)
  },

  updated(this: DebuggerSpeakerContext) {
    syncSpeakerSampleCatalog(this)
    playSpeakerFromHook(this)
  }
}

function readSpeakerEffectSeq(hook: DebuggerSpeakerContext): number {
  const raw = hook.el.dataset.speakerEffect
  if (!raw) return 0
  try {
    const effect = JSON.parse(raw) as SpeakerEffectWire
    return effect.seq ?? 0
  } catch {
    return 0
  }
}

function syncSpeakerSampleCatalog(hook: DebuggerSpeakerContext): void {
  const raw = hook.el.dataset.speakerSamples
  if (!raw) {
    setSpeakerSampleCatalog([])
    return
  }
  try {
    setSpeakerSampleCatalog(JSON.parse(raw) as SpeakerSampleWire[])
  } catch {
    setSpeakerSampleCatalog([])
  }
}

function playSpeakerFromHook(hook: DebuggerSpeakerContext): void {
  const raw = hook.el.dataset.speakerEffect
  if (!raw) return
  try {
    const effect = JSON.parse(raw) as SpeakerEffectWire
    const seq = effect.seq ?? 0
    if (seq <= (hook.lastSeq ?? 0)) return
    hook.lastSeq = seq
    void playSpeakerEffect(effect)
  } catch {
    // ignore malformed payloads
  }
}

const Hooks = {
  FirebaseAuthRefresh,
  TokenEditor,
  EditorDocsResizer,
  DebuggerShortcuts,
  DebuggerSpeaker,
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
const firebaseBootstrapConfig = authConfigFromElement(document.body)
const onFirebaseBridge = window.location.pathname === FIREBASE_BRIDGE_PATH

if (onFirebaseBridge && firebaseBootstrapConfig) {
  void runFirebaseOAuthBridge(firebaseBootstrapConfig)
} else if (firebaseBootstrapConfig) {
  completeFirebaseRedirect(firebaseBootstrapConfig).then(navigatingAway => {
    if (!navigatingAway) liveSocket.connect()
  })
} else {
  liveSocket.connect()
}

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
