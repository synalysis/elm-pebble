import {
  applySimulatorSettingsToQemu,
  BUTTONS,
  encodeAccel,
  encodeBattery,
  encodeCompass,
  QEMU
} from "./qemu_control.js"
const CONFIG_RETURN_PATH = "/api/emulator/config-return"
const MAX_LOG_LINES = 300
const MAX_LOG_CHARS = 40000
const PUTBYTES_SUMMARY_INTERVAL = 25
const SYSTEM_LOG_SUMMARY_INTERVAL = 50
const PHONE_BRIDGE_INSTALL_TIMEOUT_MS = 120000
const DISPLAY_READY_TIMEOUT_MS = 90_000
const DISPLAY_READY_POLL_MS = 50
const VNC_WS_OPEN_TIMEOUT_MS = 10_000
const VNC_CONNECT_TIMEOUT_MS = 12_000
const VNC_RECONNECT_BASE_MS = 150
const VNC_RECONNECT_MAX_MS = 3_000
const ENDPOINT_SYSTEM_LOG = 0x07d2
const ENDPOINT_APP_LOG = 0x07d6
const ENDPOINT_DATA_LOGGING = 0x1a7a
const DEBUG_STORAGE = {
  op: 0x454c4d00,
  key: 0x454c4d01,
  type: 0x454c4d02,
  intValue: 0x454c4d03,
  stringValue: 0x454c4d04,
  opWrite: 1,
  opDelete: 2,
  opSnapshot: 4,
  typeInt: 1,
  typeString: 2
}
const DEBUG_SIMULATOR = {
  compassHeading: 0x454c4d10,
  dictationText: 0x454c4d11,
  weatherTemperatureC: 0x454c4d12,
  weatherConditionWire: 0x454c4d13
}
const DEFAULT_SIMULATOR_WEATHER = {
  temperatureC: 21,
  condition: "clear"
}
const WEATHER_CONDITION_WIRE_CODES = {
  clear: 1,
  cloudy: 2,
  fog: 3,
  drizzle: 4,
  rain: 5,
  snow: 6,
  showers: 7,
  storm: 8,
  unknownweather: 9
}

import {disconnectUserSocket, getUserSocket, waitForUserSocketOpen} from "../user_socket"

const EMBEDDED_EMULATOR_UI_BUILD = "2025-05-27-vnc-phoenix-channel-v21"
const PHOENIX_SOCKET_OPEN_TIMEOUT_MS = 10_000
const VNC_CHANNEL_JOIN_TIMEOUT_MS = 10_000

let rfbModulePromise = null

function loadRFB() {
  if (!rfbModulePromise) {
    rfbModulePromise = import("@novnc/novnc")
      .then(module => module.default)
      .catch(error => {
        rfbModulePromise = null
        const blocked =
          error?.message?.includes("Failed to fetch") || error?.name === "TypeError"
        const hint = blocked
          ? " (check browser console for COEP/CORP blocked script — hard refresh after server restart)"
          : ""
        throw new Error(`Could not load noVNC display client${hint}: ${error?.message || error}`)
      })
  }
  return rfbModulePromise
}

const csrfToken = () => document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
const persistedStateFields = [
  "session",
  "buttonState",
  "launching",
  "installing",
  "appInstalled",
  "stopping",
  "pendingPypkjsInstall",
  "currentStatus",
  "logLines",
  "storageEntries",
  "suppressedPutBytesFrames",
  "suppressedSystemLogFrames",
  "sessionEnded",
  "phoneBridgeActive",
  "dataLogEntries",
  "rfb",
  "rfbCanvas",
  "vncConnecting",
  "reconnectingVnc",
  "vncReconnectTimer",
  "vncReconnectAttempts"
]
const embeddedEmulatorStates = window.__elmPebbleEmbeddedEmulatorStates ||= new Map()

function emulatorStateKey(el) {
  return el.dataset.projectSlug || "default"
}

function defaultEmulatorState(key) {
  return {
    key,
    session: null,
    buttonState: 0,
    launching: false,
    installing: false,
    appInstalled: false,
    stopping: false,
    pendingPypkjsInstall: null,
    currentStatus: null,
    logLines: [],
    storageEntries: new Map(),
    suppressedPutBytesFrames: 0,
    suppressedSystemLogFrames: 0,
    sessionEnded: false,
    sessionAlive: false,
    displayConnected: false,
    phoneBridgeReady: false,
    phoneBridgeActive: false,
    dataLogEntries: [],
    rfb: null,
    rfbCanvas: null,
    vncConnecting: false,
    reconnectingVnc: false,
    vncReconnectTimer: null,
    vncReconnectAttempts: 0,
    listeners: new Set()
  }
}

function emulatorStateFor(el) {
  const key = emulatorStateKey(el)
  if (!embeddedEmulatorStates.has(key)) embeddedEmulatorStates.set(key, defaultEmulatorState(key))
  return embeddedEmulatorStates.get(key)
}

function definePersistedState(host) {
  persistedStateFields.forEach(field => {
    Object.defineProperty(host, field, {
      get() {
        return this.state[field]
      },
      set(value) {
        this.state[field] = value
      }
    })
  })
}

function agentDebugLog(runId, hypothesisId, location, message, data = {}) {
  fetch("http://127.0.0.1:7308/ingest/2a69f066-12c8-491a-a0be-5118a68d7127", {
    method: "POST",
    headers: {"Content-Type": "application/json", "X-Debug-Session-Id": "edf96a"},
    body: JSON.stringify({sessionId: "edf96a", runId, hypothesisId, location, message, data, timestamp: Date.now()})
  }).catch(() => {})
}

async function postJSON(url, body = {}, {timeoutMs} = {}) {
  const controller = timeoutMs ? new AbortController() : null
  const timer =
    controller &&
    setTimeout(() => {
      controller.abort()
    }, timeoutMs)

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {"content-type": "application/json", "x-csrf-token": csrfToken()},
      body: JSON.stringify(body),
      signal: controller?.signal
    })
    const data = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(data.error || response.statusText)
    return data
  } catch (error) {
    if (controller?.signal.aborted) {
      throw new Error(`Request timed out after ${Math.round(timeoutMs / 1000)}s`)
    }

    throw error
  } finally {
    if (timer) clearTimeout(timer)
  }
}

function websocketURL(path) {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
  // Must match the page origin (localhost vs 127.0.0.1 are different origins in browsers).
  return `${protocol}//${window.location.host}${path}`
}

function vncWebSocketReadyStateLabel(readyState) {
  switch (readyState) {
    case WebSocket.CONNECTING:
      return "CONNECTING"
    case WebSocket.OPEN:
      return "OPEN"
    case WebSocket.CLOSING:
      return "CLOSING"
    case WebSocket.CLOSED:
      return "CLOSED"
    default:
      return readyState == null ? "missing" : String(readyState)
  }
}

export class EmbeddedEmulatorHost {
  constructor(hook) {
    this.hook = hook
    this.el = hook.el
    this.state = emulatorStateFor(this.el)
    definePersistedState(this)
    this.phoneSocket = null
    this.pingTimer = null
    this.configUrl = null
    this.configPopupTimer = null
    this.phoneOpenedAt = 0
    this.logFlushScheduled = false
    this.destroyed = false
    this.simulatorSettings = null
    this.lastAppliedSimulatorSettingsJson = null
    this.simulatorSettingsSource = null
    this.simulatorSettingsAppliedAt = 0
    this.weatherInjectTimers = []
    this.weatherPushTimer = null
    this.weatherPushRetryTimers = []
    this.weatherDebugQueue = []
    this.weatherDebugInFlight = false
    this.weatherDebugInFlightAt = 0
    this.weatherDebugAckTimer = null
    this.weatherDebugFallbackTimer = null
    this.pendingWeatherRetry = null
    this.lastSentWeatherJson = null
    this.vncViewportConfigKey = null
    this.vncViewportConfigTimer = null
    this.boundEmulatorButtons = new WeakSet()
    this.boundControlElements = new WeakSet()
    this.syncStateToDom = () => {
      if (this.destroyed) return
      if (this.status && this.currentStatus) this.status.textContent = this.currentStatus
      this.renderLog()
      this.renderStorage()
      this.renderDataLog()
      this.updateControlButtons()
    }
    this.handlePageVisible = () => this.ensureVncAttached()
    this.handleConfigKeyDown = event => {
      if (event.key === "Escape" && this.configPanel && !this.configPanel.classList.contains("hidden")) {
        this.cancelConfig()
      }
    }
    this.handleRootClick = event => {
      if (this.destroyed) return
      if (event.target.closest("[data-emulator-launch]")) {
        event.preventDefault()
        this.toggleLaunch()
        return
      }
      if (event.target.closest("[data-emulator-install]")) {
        event.preventDefault()
        void this.install()
        return
      }
      if (event.target.closest("[data-emulator-preferences]")) {
        event.preventDefault()
        void this.loadCompanionPreferences()
        return
      }
      if (event.target.closest("[data-emulator-screenshot]")) {
        event.preventDefault()
        void this.captureScreenshot()
        return
      }
      if (event.target.closest("[data-emulator-copy-feedback]")) {
        event.preventDefault()
        void this.copyFeedbackReport()
        return
      }
      if (event.target.closest("[data-emulator-storage-reset]")) {
        event.preventDefault()
        void this.resetStorage()
        return
      }
      if (event.target.closest("[data-emulator-storage-add]")) {
        event.preventDefault()
        void this.saveNewStorageEntry()
        return
      }
      if (event.target.closest("[data-emulator-config-cancel]")) {
        event.preventDefault()
        this.cancelConfig()
        return
      }
      if (event.target.closest("[data-emulator-tap]")) {
        event.preventDefault()
        this.sendQemu(QEMU.tap, [0, 1])
        return
      }
      if (event.target.closest("[data-emulator-compass-send]")) {
        event.preventDefault()
        this.sendCompassSample()
      }
    }
  }

  mount() {
    this.canvas = this.el.querySelector("[data-emulator-canvas]")
    this.status = this.el.querySelector("[data-emulator-status]")
    this.log = this.el.querySelector("[data-emulator-log]")
    this.configPanel = this.el.querySelector("[data-emulator-config-panel]")
    this.configDialog = this.el.querySelector("[data-emulator-config-dialog]")
    this.configFrame = this.el.querySelector("[data-emulator-config-frame]")
    this.configUrlLabel = this.el.querySelector("[data-emulator-config-url]")
    this.launchButton = this.el.querySelector("[data-emulator-launch]")
    this.installButton = this.el.querySelector("[data-emulator-install]")
    this.preferencesButton = this.el.querySelector("[data-emulator-preferences]")
    this.screenshotButton = this.el.querySelector("[data-emulator-screenshot]")
    this.storageRows = this.el.querySelector("[data-emulator-storage-rows]")
    this.storageResetButton = this.el.querySelector("[data-emulator-storage-reset]")
    this.storageAddButton = this.el.querySelector("[data-emulator-storage-add]")
    this.storageNewKey = this.el.querySelector("[data-emulator-storage-new-key]")
    this.storageNewType = this.el.querySelector("[data-emulator-storage-new-type]")
    this.storageNewValue = this.el.querySelector("[data-emulator-storage-new-value]")
    this.dataLogRows = this.el.querySelector("[data-emulator-data-log-rows]")
    document.addEventListener("keydown", this.handleConfigKeyDown)
    this.el.addEventListener("click", this.handleRootClick)

    this.bindControlButtons()
    this.bindEmulatorButtons()
    this.state.listeners.add(this.syncStateToDom)
    window.addEventListener("focus", this.handlePageVisible)
    document.addEventListener("visibilitychange", this.handlePageVisible)
    this.applyInitialSimulatorSettings()
    if (!this.session) {
      this.launching = false
      this.stopping = false
    }
    void this.initializePersistedSession()
    this.applyCanvasSize()
    this.syncStateToDom()
    if (!window.isSecureContext) {
      this.appendLog("Embedded emulator display requires a secure browser context (https:// or http://localhost)")
    }
  }

  updated() {
    const previousCanvas = this.canvas
    this.refreshSimulatorCapabilities()
    this.canvas = this.el.querySelector("[data-emulator-canvas]")
    this.status = this.el.querySelector("[data-emulator-status]")
    this.log = this.el.querySelector("[data-emulator-log]")
    this.launchButton = this.el.querySelector("[data-emulator-launch]")
    this.installButton = this.el.querySelector("[data-emulator-install]")
    this.preferencesButton = this.el.querySelector("[data-emulator-preferences]")
    this.screenshotButton = this.el.querySelector("[data-emulator-screenshot]")
    this.storageRows = this.el.querySelector("[data-emulator-storage-rows]")
    this.storageResetButton = this.el.querySelector("[data-emulator-storage-reset]")
    this.storageAddButton = this.el.querySelector("[data-emulator-storage-add]")

    if (this.status && this.currentStatus) {
      this.status.textContent = this.currentStatus
    }
    this.renderLog()
    this.renderStorage()
    this.renderDataLog()
    this.bindControlButtons()
    this.bindEmulatorButtons()
    this.updateControlButtons()
    this.applyCanvasSize()
    this.syncSimulatorSettingsFromDataset()
    if (this.session?.backend_enabled && this.rfb && previousCanvas && previousCanvas !== this.canvas) {
      // #region agent log
      agentDebugLog("initial", "H19", "embedded_emulator.js:updated:canvas_replaced", "emulator canvas replaced during liveview update", {
        sessionId: this.session?.id,
        previousConnected: this.rfb?._rfbConnectionState,
        hasPreviousCanvas: !!previousCanvas,
        hasNewCanvas: !!this.canvas
      })
      // #endregion
      this.reconnectVncAfterDomPatch()
    }
    this.ensureVncAttached()
  }

  async initializePersistedSession() {
    if (!this.session) {
      this.updateControlButtons()
      return
    }

    await this.validatePersistedSession()
    if (!this.session) {
      this.updateControlButtons()
      return
    }

    this.resumeExistingSession()
    this.ensureVncAttached()
    this.updateControlButtons()
  }

  async validatePersistedSession() {
    if (!this.session) return

    this.sessionAlive = false
    this.displayConnected = false
    this.phoneBridgeReady = false

    try {
      const response = await postJSON(this.session.ping_path)
      if (response?.alive !== true) {
        this.endSession("Previous emulator session has ended")
        return
      }

      this.sessionAlive = true
    } catch (_error) {
      this.endSession("Previous emulator session is unreachable")
    }
  }

  resumeExistingSession() {
    if (!this.session) return

    this.sessionEnded = false
    this.applyCanvasSize()
    if (this.session.backend_enabled && !(this.rfb && this.rfbCanvas === this.canvas)) {
      this.connectDisplay().catch(error => {
        if (this.session && !this.stopping && !this.destroyed) {
          this.scheduleVncReconnect(`Embedded emulator display reconnect failed: ${error.message}`)
        }
      })
    }
    if (this.sessionAlive) this.schedulePingAfterDisplayConnect()
    this.reapplySimulatorSettingsToQemu({source: "session_resume", quiet: true})
  }

  destroy(removeListeners = true) {
    this.destroyed = true
    this.state.listeners.delete(this.syncStateToDom)
    this.stopPingAfterDisplayTimer()
    this.stopPing()
    this.stopVncReconnect()
    this.stopConfigPopupPolling()
    if (this.vncViewportConfigTimer) {
      window.clearTimeout(this.vncViewportConfigTimer)
      this.vncViewportConfigTimer = null
    }
    this.vncViewportConfigKey = null
    this.weatherInjectTimers.forEach(timerId => window.clearTimeout(timerId))
    this.weatherInjectTimers = []
    this.weatherPushRetryTimers.forEach(timerId => window.clearTimeout(timerId))
    this.weatherPushRetryTimers = []
    if (this.weatherDebugFallbackTimer != null) {
      window.clearTimeout(this.weatherDebugFallbackTimer)
      this.weatherDebugFallbackTimer = null
    }
    if (this.weatherDebugAckTimer != null) {
      window.clearTimeout(this.weatherDebugAckTimer)
      this.weatherDebugAckTimer = null
    }
    this.weatherDebugQueue = []
    this.weatherDebugInFlight = false
    this.pendingWeatherRetry = null
    if (this.weatherPushTimer != null) {
      window.clearTimeout(this.weatherPushTimer)
      this.weatherPushTimer = null
    }
    window.removeEventListener("focus", this.handlePageVisible)
    document.removeEventListener("visibilitychange", this.handlePageVisible)
    if (removeListeners) document.removeEventListener("keydown", this.handleConfigKeyDown)
    this.el.removeEventListener("click", this.handleRootClick)
    this.releaseAllButtons()
    if (this.rfb) {
      const oldRfb = this.rfb
      this.rfb = null
      this.rfbCanvas = null
      this.disconnectRfb(oldRfb)
    }
    if (this.phoneSocket) this.phoneSocket.close()
  }

  notifyStateChanged() {
    this.state.listeners.forEach(listener => listener())
  }

  toggleLaunch() {
    if (this.launching || this.stopping) return
    if (this.session && this.sessionAlive && !this.sessionEnded) {
      void this.stop()
      return
    }
    if (this.session) {
      this.session = null
      this.sessionEnded = false
      this.launching = false
      this.stopping = false
    }
    void this.launch()
  }

  async launch() {
    if (this.launching) return
    if (this.session) return

    const slug = this.el.dataset.projectSlug
    const platform = this.el.dataset.emulatorTarget
    if (!slug || !platform) {
      this.setStatus("Embedded emulator is missing project slug or watch model")
      return
    }

    this.launching = true
    this.notifyStateChanged()

    try {
      this.clearLog()
      this.hideConfigPage()
      this.sessionEnded = false
      this.appInstalled = false
      this.setStatus("Launching embedded emulator...")
      void loadRFB().catch(() => {})
      const payload = {slug, platform}
      this.session = await postJSON("/api/emulator/launch", payload)
      this.sessionAlive = true
      this.displayConnected = false
      this.phoneBridgeReady = false
      // #region agent log
      agentDebugLog("initial", "H19,H20,H21", "embedded_emulator.js:launch:session", "emulator launch response received in browser", {
        sessionId: this.session?.id,
        backendEnabled: this.session?.backend_enabled,
        vncPath: this.session?.vnc_path,
        screen: this.session?.screen
      })
      // #endregion
      if (!this.destroyed) {
        this.warnSessionScreenMismatch()
        this.logEmulatorPlatform()
        this.applyCanvasSize()
        const displayReady = await this.waitForDisplayReady()
        if (!displayReady && this.session && !this.destroyed) {
          this.appendLog("Embedded emulator VNC port was not ready before display connect timed out")
        }
        await this.connectDisplay()
        if (this.session && !this.destroyed) this.schedulePingAfterDisplayConnect()
      }
      if (this.session?.backend_enabled && this.displayConnected) {
        this.setStatus("Embedded emulator display connected")
      } else if (this.session?.backend_enabled) {
        this.setStatus("Embedded emulator session started; connecting display...")
      } else {
        this.setStatus("Embedded emulator backend disabled; launch API is in dry-run mode")
      }
      this.reapplySimulatorSettingsToQemu({source: "after_launch", quiet: true})
    } catch (error) {
      this.setStatus(`Embedded emulator failed: ${error.message}`)
    } finally {
      this.launching = false
      this.notifyStateChanged()
    }
  }

  async stop() {
    if (!this.session || this.stopping) return
    const session = this.session
    this.stopping = true
    this.notifyStateChanged()

    try {
      await postJSON(session.kill_path)
      this.endSession("Embedded emulator stopped")
    } catch (error) {
      this.setStatus(`Could not stop embedded emulator: ${error.message}`)
    } finally {
      this.stopping = false
      this.notifyStateChanged()
    }
  }

  resolveCanvas() {
    this.canvas = this.el.querySelector("[data-emulator-canvas]")
    return this.canvas
  }

  async waitForDisplayReady(timeoutMs = DISPLAY_READY_TIMEOUT_MS) {
    if (!this.session?.backend_enabled) return true
    if (this.session.display_ready) return true

    const deadline = Date.now() + timeoutMs
    const pingPath = this.session.ping_path

    while (Date.now() < deadline) {
      if (this.destroyed || !this.session) return false

      try {
        const info = await postJSON(pingPath)
        if (info.display_ready) {
          Object.assign(this.session, info)
          return true
        }
      } catch (_error) {
        // Session may still be booting QEMU/VNC.
      }

      await new Promise(resolve => window.setTimeout(resolve, DISPLAY_READY_POLL_MS))
    }

    return !!this.session?.display_ready
  }

  async connectDisplay() {
    if (this.destroyed || !this.session?.backend_enabled) return

    for (let attempt = 0; attempt < 20 && !this.resolveCanvas(); attempt += 1) {
      await new Promise(resolve => window.requestAnimationFrame(resolve))
    }

    if (!this.canvas) {
      this.appendLog("Embedded emulator display element not found in the page")
      return
    }

    if (!this.session.display_ready) {
      await this.waitForDisplayReady(15_000)
    }

    this.appendLog(`Connecting embedded emulator display (${this.session.vnc_path})`)

    try {
      await this.connectVnc()
    } catch (error) {
      this.appendLog(`Embedded emulator display failed: ${error.message}`)
    }
  }

  closeVncSocket() {
    if (this.vncSocket) {
      try {
        this.vncSocket.close()
      } catch (_error) {
        // Socket may already be closed.
      }
      this.vncSocket = null
    }
  }

  closeVncChannel() {
    if (this.vncChannel) {
      try {
        this.vncChannel.leave()
      } catch (_error) {
        // Channel may already be closed.
      }
      this.vncChannel = null
    }
    this.resetVncFramePipeline()
    this.vncPhoenixSocket = null
  }

  disconnectRfb(rfb, {reconnecting = false} = {}) {
    if (reconnecting) this.reconnectingVnc = true
    if (rfb) {
      try {
        rfb.disconnect()
      } catch (_error) {
        // noVNC may already be disconnected.
      }
    }
    this.closeVncChannel()
    this.closeVncSocket()
  }

  ensurePhoenixSocket() {
    const socket = getUserSocket({onLog: message => this.appendLog(message)})
    this.vncPhoenixSocket = socket
    return socket
  }

  decodeChannelBinary(payload) {
    if (payload instanceof ArrayBuffer) return payload
    if (ArrayBuffer.isView(payload)) {
      return payload.buffer.slice(payload.byteOffset, payload.byteOffset + payload.byteLength)
    }
    if (payload && typeof payload === "object") {
      const encoded = payload.b64 ?? payload["b64"]
      if (typeof encoded === "string") return this.base64ToArrayBuffer(encoded)
    }
    if (typeof payload === "string") {
      return this.base64ToArrayBuffer(payload)
    }
    return null
  }

  base64ToArrayBuffer(encoded) {
    const binary = atob(encoded)
    const bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i)
    return bytes.buffer
  }

  vncBytes(data) {
    if (data instanceof ArrayBuffer) return new Uint8Array(data)
    if (ArrayBuffer.isView(data)) {
      return new Uint8Array(data.buffer, data.byteOffset, data.byteLength)
    }
    throw new Error(`unsupported VNC frame data (${data?.constructor?.name || typeof data})`)
  }

  bytesToBase64(bytes) {
    let binary = ""
    const chunk = 0x8000
    for (let i = 0; i < bytes.length; i += chunk) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk))
    }
    return btoa(binary)
  }

  pushVncFrame(channel, data) {
    const bytes = this.vncBytes(data)
    if (!this.vncLoggedFirstSend) {
      this.vncLoggedFirstSend = true
      this.appendLog(`Embedded emulator VNC pushing ${bytes.length} byte(s) to channel`)
    }
    channel.push("frame", {b64: this.bytesToBase64(bytes)})
  }

  resetVncFramePipeline() {
    this.vncPendingFrames = []
    this.vncFrameSink = null
    this.vncJoinInitial = null
  }

  enqueueVncChannelFrame(payload) {
    const data = this.decodeChannelBinary(payload)
    if (!data) {
      const kind = payload == null ? "null" : payload?.constructor?.name || typeof payload
      this.appendLog(`Embedded emulator VNC ignored frame payload (${kind})`)
      return
    }
    const chunkBytes = data.byteLength || 0
    if (this.vncWsDiag) {
      this.vncWsDiag.bytesReceived += chunkBytes
      this.vncWsDiag.framesReceived += 1
    }
    if (this.vncFrameSink) {
      this.vncFrameSink(data)
    } else {
      this.vncPendingFrames.push(data)
    }
  }

  bindVncFrameSink(deliver) {
    this.vncFrameSink = deliver
    const pending = this.vncPendingFrames
    this.vncPendingFrames = []
    for (const data of pending) deliver(data)
  }

  deliverVncJoinInitial(rfb) {
    const data = this.vncJoinInitial
    if (!data || !rfb?._sock?._recvMessage) return

    this.vncJoinInitial = null
    rfb._sock._recvMessage({data})
    this.appendLog(`Embedded emulator delivered ${data.byteLength} byte(s) join initial to noVNC`)
  }

  async joinVncChannel() {
    const socket = this.ensurePhoenixSocket()
    const topic = `emulator_vnc:${this.session.id}`

    this.appendLog(`Opening Phoenix user socket (state=${socket.connectionState()})`)
    await waitForUserSocketOpen(socket, PHOENIX_SOCKET_OPEN_TIMEOUT_MS, {
      onLog: message => this.appendLog(message)
    })
    this.appendLog("Phoenix user socket open; joining emulator VNC channel")

    this.resetVncFramePipeline()
    const channel = socket.channel(topic, {})
    // Register before join: the server may push the RFB banner as soon as the relay starts.
    channel.on("frame", payload => this.enqueueVncChannelFrame(payload))

    return new Promise((resolve, reject) => {
      let settled = false
      const finish = (error, joinedChannel = null) => {
        if (settled) return
        settled = true
        window.clearTimeout(timer)
        if (error) reject(error)
        else resolve(joinedChannel)
      }

      const timer = window.setTimeout(() => {
        finish(
          new Error(
            `Phoenix channel join timed out after ${VNC_CHANNEL_JOIN_TIMEOUT_MS / 1000}s (socket=${socket.connectionState()})`
          )
        )
      }, VNC_CHANNEL_JOIN_TIMEOUT_MS)

      channel
        .join()
        .receive("ok", response => {
          if (response?.initial) {
            try {
              const binary = atob(response.initial)
              const bytes = new Uint8Array(binary.length)
              for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i)
              // Hold until noVNC has attached the transport and run _socketOpen(); feeding the
              // RFB banner earlier triggers "Unknown init state" and the handshake never starts.
              this.vncJoinInitial = bytes.buffer
              if (this.vncWsDiag) this.vncWsDiag.bytesReceived += bytes.byteLength
              this.appendLog(
                `Embedded emulator VNC channel received ${bytes.byteLength} byte(s) in join reply (held for noVNC init)`
              )
            } catch (error) {
              this.appendLog(`Embedded emulator VNC join initial decode failed: ${error.message}`)
            }
          }
          finish(null, channel)
        })
        .receive("error", response => {
          finish(new Error(`Phoenix channel join failed: ${JSON.stringify(response)}`))
        })
        .receive("timeout", () => finish(new Error("Phoenix channel join timeout")))
    })
  }

  createVncChannelTransport(channel) {
    let onopen = null
    let onmessage = null
    let onerror = null
    let onclose = null
    const pendingForTransport = []

    const deliverToTransport = data => {
      if (onmessage) onmessage({data})
      else pendingForTransport.push(data)
    }

    const flushPendingForTransport = () => {
      if (!onmessage || pendingForTransport.length === 0) return
      const pending = pendingForTransport.splice(0)
      for (const data of pending) onmessage({data})
    }

    this.bindVncFrameSink(deliverToTransport)

    channel.onError(() => {
      if (this.vncWsDiag) this.vncWsDiag.error = "phoenix channel error"
      if (onerror) onerror(new Event("error"))
    })

    channel.onClose(() => {
      if (this.vncWsDiag) {
        this.vncWsDiag.closed = true
        this.vncWsDiag.open = false
      }
      if (onclose) onclose(new CloseEvent("close"))
    })

    return {
      binaryType: "arraybuffer",
      protocol: "",
      bufferedAmount: 0,
      readyState: WebSocket.OPEN,
      send: data => {
        this.pushVncFrame(channel, data)
      },
      close: () => {
        channel.leave()
      },
      get onopen() {
        return onopen
      },
      set onopen(fn) {
        onopen = fn
      },
      get onmessage() {
        return onmessage
      },
      set onmessage(fn) {
        onmessage = fn
        flushPendingForTransport()
      },
      get onerror() {
        return onerror
      },
      set onerror(fn) {
        onerror = fn
      },
      get onclose() {
        return onclose
      },
      set onclose(fn) {
        onclose = fn
      }
    }
  }

  resetVncWsDiag() {
    this.vncLoggedFirstSend = false
    this.vncWsDiag = {
      url: null,
      readyState: null,
      readyStateLabel: "missing",
      open: false,
      closed: false,
      closeCode: null,
      closeReason: null,
      error: null,
      bytesReceived: 0,
      framesReceived: 0
    }
  }

  attachVncWebSocketDiagnostics(ws) {
    if (!ws || ws.__elmPebbleVncDiag) return
    ws.__elmPebbleVncDiag = true

    const refreshReadyState = () => {
      this.vncWsDiag.readyState = ws.readyState
      this.vncWsDiag.readyStateLabel = vncWebSocketReadyStateLabel(ws.readyState)
    }

    refreshReadyState()

    ws.addEventListener("open", () => {
      refreshReadyState()
      this.vncWsDiag.open = true
      this.appendLog("Embedded emulator VNC websocket open")
    })
    ws.addEventListener("message", event => {
      const chunkBytes =
        event.data instanceof ArrayBuffer
          ? event.data.byteLength
          : typeof event.data === "string"
            ? event.data.length
            : 0
      this.vncWsDiag.bytesReceived += chunkBytes
      this.vncWsDiag.framesReceived += 1
    })
    ws.addEventListener("error", () => {
      refreshReadyState()
      this.vncWsDiag.error = "websocket error"
    })
    ws.addEventListener("close", event => {
      refreshReadyState()
      this.vncWsDiag.closed = true
      this.vncWsDiag.closeCode = event.code
      this.vncWsDiag.closeReason = event.reason || null
    })
  }

  async probeEmulatorSession(pingPath) {
    const started = performance.now()

    try {
      const info = await postJSON(pingPath)
      return {
        ok: true,
        ms: Math.round(performance.now() - started),
        alive: info?.alive === true,
        display_ready: info?.display_ready === true
      }
    } catch (error) {
      return {
        ok: false,
        ms: Math.round(performance.now() - started),
        error: error?.message || String(error)
      }
    }
  }

  openVncWebSocket(url) {
    this.resetVncWsDiag()
    this.vncWsDiag.url = url
    this.closeVncSocket()

    return new Promise((resolve, reject) => {
      let settled = false
      let ws

      const finish = (error, socket = null) => {
        if (settled) return
        settled = true
        window.clearInterval(stateTimer)
        window.clearTimeout(openTimer)
        if (error) {
          this.closeVncSocket()
          reject(error)
        } else {
          resolve(socket)
        }
      }

      try {
        ws = new WebSocket(url)
      } catch (error) {
        finish(new Error(`WebSocket constructor failed: ${error.message}`))
        return
      }

      ws.binaryType = "arraybuffer"
      this.vncSocket = ws
      this.attachVncWebSocketDiagnostics(ws)

      const stateTimer = window.setInterval(() => {
        if (!this.vncWsDiag || ws !== this.vncSocket) return
        this.vncWsDiag.readyState = ws.readyState
        this.vncWsDiag.readyStateLabel = vncWebSocketReadyStateLabel(ws.readyState)
      }, 250)

      const openTimer = window.setTimeout(() => {
        const label = vncWebSocketReadyStateLabel(ws.readyState)
        finish(
          new Error(
            `WebSocket did not open within ${VNC_WS_OPEN_TIMEOUT_MS / 1000}s (${label}); check IDE server logs for emulator websocket proxy errors`
          )
        )
      }, VNC_WS_OPEN_TIMEOUT_MS)

      ws.addEventListener(
        "open",
        () => {
          finish(null, ws)
        },
        {once: true}
      )

      ws.addEventListener(
        "error",
        () => {
          const label = vncWebSocketReadyStateLabel(ws.readyState)
          finish(new Error(`WebSocket error before open (${label})`))
        },
        {once: true}
      )

      ws.addEventListener(
        "close",
        event => {
          if (ws.readyState === WebSocket.OPEN) return
          const reason = event.reason ? `: ${event.reason}` : ""
          finish(
            new Error(
              `WebSocket closed before open (code ${event.code}${reason}, state ${vncWebSocketReadyStateLabel(ws.readyState)})`
            )
          )
        },
        {once: true}
      )
    })
  }

  async connectVnc() {
    if (this.destroyed || !this.session?.backend_enabled || !this.canvas) return
    if (this.vncConnecting) return
    this.vncConnecting = true
    if (this.rfb) {
      const previousRfb = this.rfb
      this.rfb = null
      this.rfbCanvas = null
      this.disconnectRfb(previousRfb, {reconnecting: this.displayConnected})
    }
    if (this.destroyed || !this.session?.backend_enabled || !this.canvas) {
      this.vncConnecting = false
      return
    }
    let RFB
    try {
      RFB = await loadRFB()
    } catch (error) {
      this.vncConnecting = false
      throw error
    }
    if (this.destroyed || !this.session?.backend_enabled || !this.canvas) {
      this.vncConnecting = false
      return
    }
    const sessionProbe = await this.probeEmulatorSession(this.session.ping_path)
    this.vncSessionProbe = sessionProbe
    if (sessionProbe.ok) {
      this.appendLog(
        `Embedded emulator session probe ok in ${sessionProbe.ms}ms (alive=${sessionProbe.alive}, display_ready=${sessionProbe.display_ready})`
      )
    } else {
      this.appendLog(`Embedded emulator session probe failed in ${sessionProbe.ms}ms: ${sessionProbe.error}`)
    }
    this.appendLog(`Connecting embedded emulator display via Phoenix channel (emulator_vnc:${this.session.id})`)
    this.resetVncWsDiag()
    let channel
    try {
      channel = await this.joinVncChannel()
      this.vncChannel = channel
      this.appendLog("Embedded emulator VNC channel joined")
    } catch (error) {
      this.vncConnecting = false
      this.appendLog(`Embedded emulator VNC channel failed: ${error.message}`)
      throw error
    }
    if (this.destroyed || !this.session?.backend_enabled || !this.canvas) {
      this.vncConnecting = false
      this.closeVncChannel()
      return
    }
    const transport = this.createVncChannelTransport(channel)
    const bytesReceived = this.vncWsDiag?.bytesReceived || 0
    const framesReceived = this.vncWsDiag?.framesReceived || 0
    this.vncWsDiag.url = `phoenix:/socket/emulator_vnc:${this.session.id}`
    Object.assign(this.vncWsDiag, {
      readyState: WebSocket.OPEN,
      readyStateLabel: "OPEN",
      open: true,
      closed: false,
      closeCode: null,
      closeReason: null,
      error: null,
      bytesReceived,
      framesReceived
    })
    let rfb
    try {
      rfb = new RFB(this.canvas, transport, {
        shared: true,
        credentials: {password: ""}
      })
      this.deliverVncJoinInitial(rfb)
    } catch (error) {
      this.vncConnecting = false
      this.closeVncChannel()
      throw error
    }
    this.rfb = rfb
    this.rfbCanvas = this.canvas
    this.vncViewportConfigKey = null
    this.vncConnecting = false
    this.reconnectingVnc = false
    this.updateControlButtons()
    // #region agent log
    agentDebugLog("initial", "H19,H20,H21", "embedded_emulator.js:vnc:create", "noVNC RFB object created", {
      sessionId: this.session?.id,
      vncPath: this.session?.vnc_path,
      canvasWidth: this.canvas?.width,
      canvasHeight: this.canvas?.height,
      clientWidth: this.canvas?.clientWidth,
      clientHeight: this.canvas?.clientHeight
    })
    // #endregion
    rfb.resizeSession = false
    const connectTimeout = window.setTimeout(() => {
      if (this.destroyed || rfb !== this.rfb || this.displayConnected) return
      const diag = this.vncWsDiag || {}
      const wsState = diag.readyStateLabel || "unknown"
      const wsHint = diag.open
        ? diag.bytesReceived > 0
          ? `VNC transport received ${diag.bytesReceived} bytes in ${diag.framesReceived} frame(s) but noVNC did not finish the handshake`
          : this.vncPendingFrames?.length > 0
            ? `VNC transport has ${this.vncPendingFrames.length} buffered frame(s) waiting for noVNC`
            : "VNC transport open but no binary frames received from the server"
        : diag.closed
          ? `VNC transport closed (code ${diag.closeCode ?? "?"}, state ${wsState})`
          : diag.error
            ? `${diag.error} (state ${wsState})`
            : `VNC transport did not open (state ${wsState})`
      this.appendLog(
        `Embedded emulator display connect timed out (no VNC response within ${VNC_CONNECT_TIMEOUT_MS / 1000}s; ${wsHint})`
      )
      this.disconnectRfb(rfb, {reconnecting: true})
      if (this.session && !this.stopping) {
        this.scheduleVncReconnect("Embedded emulator display timed out; reconnecting...")
      }
    }, VNC_CONNECT_TIMEOUT_MS)
    rfb.addEventListener("credentialsrequired", () => {
      if (this.destroyed || rfb !== this.rfb) return
      try {
        rfb.sendCredentials({password: ""})
      } catch (error) {
        this.appendLog(`Embedded emulator display credentials failed: ${error.message}`)
      }
    })
    rfb.addEventListener("securityfailure", event => {
      if (this.destroyed || rfb !== this.rfb) return
      window.clearTimeout(connectTimeout)
      const reason = event?.detail?.reason || "security failure"
      this.appendLog(`Embedded emulator display security failure: ${reason}`)
      this.disconnectRfb(rfb, {reconnecting: true})
      if (this.session && !this.stopping) {
        this.scheduleVncReconnect(`Embedded emulator display security failure; reconnecting...`)
      }
    })
    rfb.addEventListener("connectfailed", event => {
      if (this.destroyed || rfb !== this.rfb) return
      window.clearTimeout(connectTimeout)
      const reason = event?.detail?.reason || "connect failed"
      this.appendLog(`Embedded emulator display connect failed: ${reason}`)
      this.disconnectRfb(rfb, {reconnecting: true})
      if (this.session && !this.stopping) {
        this.scheduleVncReconnect(`Embedded emulator display connect failed; reconnecting...`)
      }
    })
    rfb.addEventListener("connect", () => {
      if (this.destroyed) return
      if (rfb !== this.rfb) return
      window.clearTimeout(connectTimeout)
      this.stopVncReconnect()
      this.vncReconnectAttempts = 0
      // #region agent log
      agentDebugLog("initial", "H20,H21", "embedded_emulator.js:vnc:connect", "noVNC connected", {
        sessionId: this.session?.id,
        canvasWidth: this.canvas?.width,
        canvasHeight: this.canvas?.height,
        clientWidth: this.canvas?.clientWidth,
        clientHeight: this.canvas?.clientHeight
      })
      // #endregion
      this.scheduleVncViewportConfig(rfb, "connect", 100)
      this.scheduleVncViewportConfig(rfb, "connect_1s", 1000)
      this.scheduleVncViewportConfig(rfb, "connect_3s", 3000)
      this.scheduleVncCanvasSample("after_connect")
      this.scheduleVncCanvasSample("after_connect_1s", 1000)
      if (this.session && !this.stopping) {
        this.displayConnected = true
        this.setStatus("Embedded emulator display connected")
        this.stopPingAfterDisplayTimer()
        if (!this.destroyed && !this.pingTimer) this.startPing()
        this.connectPhone()
      }
    })
    rfb.addEventListener("framebufferresize", () => {
      if (this.destroyed) return
      if (rfb !== this.rfb) return
      this.scheduleVncViewportConfig(rfb, "framebufferresize")
    })
    rfb.addEventListener("disconnect", event => {
      if (this.destroyed) return
      if (rfb !== this.rfb) return
      window.clearTimeout(connectTimeout)
      if (this.reconnectingVnc) return
      // #region agent log
      agentDebugLog("initial", "H19,H20", "embedded_emulator.js:vnc:disconnect", "noVNC disconnected", {
        sessionId: this.session?.id,
        clean: event?.detail?.clean,
        reconnecting: this.reconnectingVnc,
        stopping: this.stopping
      })
      // #endregion
      const detail = event?.detail
      const status = detail?.status
      const clean = detail?.clean
      const reason = clean ? "clean disconnect" : `disconnect (status ${status ?? "?"})`
      if (this.session && !this.stopping) {
        this.appendLog(`Embedded emulator display ${reason}`)
        this.scheduleVncReconnect("Embedded emulator display disconnected; reconnecting...")
      }
    })
  }

  reconnectVncAfterDomPatch() {
    this.scheduleVncReconnect("Embedded emulator display moved; reconnecting...")
  }

  ensureVncAttached() {
    if (this.destroyed || !this.session?.backend_enabled || !this.canvas || this.stopping) return
    if (document.visibilityState === "hidden") return
    if (this.rfb && this.rfbCanvas === this.canvas) return
    if (this.vncReconnectTimer || this.reconnectingVnc || this.vncConnecting) return
    void this.connectDisplay()
  }

  scheduleVncReconnect(message) {
    if (this.destroyed || !this.session?.backend_enabled || this.stopping || this.vncReconnectTimer) return
    this.setStatus(message)
    const delay = Math.min(VNC_RECONNECT_BASE_MS * 2 ** this.vncReconnectAttempts, VNC_RECONNECT_MAX_MS)
    // #region agent log
    agentDebugLog("initial", "H19,H20", "embedded_emulator.js:vnc:reconnect_scheduled", "scheduled noVNC reconnect", {
      sessionId: this.session?.id,
      message,
      attempts: this.vncReconnectAttempts,
      delay
    })
    // #endregion
    this.vncReconnectAttempts += 1
    this.vncReconnectTimer = window.setTimeout(() => {
      this.vncReconnectTimer = null
      this.connectDisplay().catch(error => {
        this.reconnectingVnc = false
        if (this.session && !this.stopping && !this.destroyed) this.scheduleVncReconnect(`Embedded emulator display reconnect failed: ${error.message}`)
      })
    }, delay)
  }

  stopVncReconnect() {
    if (this.vncReconnectTimer) window.clearTimeout(this.vncReconnectTimer)
    this.vncReconnectTimer = null
  }

  readVncBackingSize() {
    const innerCanvas = this.canvas?.querySelector("canvas")
    if (!innerCanvas?.width || !innerCanvas?.height) return null
    return {width: innerCanvas.width, height: innerCanvas.height}
  }

  readVncFramebufferSize(rfb) {
    const fbWidth = rfb?._fbWidth ?? 0
    const fbHeight = rfb?._fbHeight ?? 0
    if (fbWidth > 0 && fbHeight > 0) {
      return {width: fbWidth, height: fbHeight}
    }
    return this.readVncBackingSize()
  }

  scheduleVncViewportConfig(rfb, reason, delayMs = 100) {
    window.setTimeout(() => {
      if (this.destroyed || rfb !== this.rfb) return
      window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => {
          this.configureVncDisplay(rfb, reason)
        })
      })
    }, delayMs)
  }

  configureVncDisplay(rfb, reason = "connect") {
    if (this.destroyed || !rfb || rfb !== this.rfb || !this.canvas) return

    const screen = this.expectedScreenSize()
    this.applyCanvasSize()
    rfb.resizeSession = false

    const framebuffer = this.readVncFramebufferSize(rfb)
    const canvasBacking = this.readVncBackingSize()
    const fbWidth = framebuffer?.width ?? 0
    const fbHeight = framebuffer?.height ?? 0
    const oversized =
      fbWidth > screen.width + 1 ||
      fbHeight > screen.height + 1
    const configKey = `${fbWidth}x${fbHeight}:${screen.width}x${screen.height}`
    if (this.vncViewportConfigKey === configKey) return
    this.vncViewportConfigKey = configKey

    // Always clip at 1:1. scaleViewport scales the entire padded QEMU surface into
    // the canvas, which shrinks a top-left draw layer into the upper-left quadrant.
    rfb.scaleViewport = false
    rfb.clipViewport = true

    const canvasNote =
      canvasBacking && (canvasBacking.width !== fbWidth || canvasBacking.height !== fbHeight)
        ? ` canvas ${canvasBacking.width}x${canvasBacking.height}`
        : ""

    this.appendLog(
      `VNC viewport ${reason}: framebuffer ${fbWidth}x${fbHeight}, screen ${screen.width}x${screen.height}, clip${oversized ? " (padded fb)" : ""}${canvasNote}`,
      {flushTransfers: false, flushSystemLogs: false}
    )
  }

  scheduleVncCanvasSample(label, delayMs = 0) {
    const sample = () => {
      window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => {
          this.logVncCanvasSample(label)
        })
      })
    }
    if (delayMs > 0) {
      window.setTimeout(sample, delayMs)
    } else {
      sample()
    }
  }

  logVncCanvasSample(label) {
    const innerCanvas = this.canvas?.querySelector("canvas")
    const wrapperRect = this.canvas?.getBoundingClientRect?.()
    const innerRect = innerCanvas?.getBoundingClientRect?.()
    const sample = {
      label,
      sessionId: this.session?.id,
      wrapperPresent: !!this.canvas,
      innerCanvasPresent: !!innerCanvas,
      wrapperSize: wrapperRect ? {width: wrapperRect.width, height: wrapperRect.height} : null,
      innerSize: innerRect ? {width: innerRect.width, height: innerRect.height} : null,
      backingSize: innerCanvas ? {width: innerCanvas.width, height: innerCanvas.height} : null,
      wrapperChildren: this.canvas ? Array.from(this.canvas.children).map(child => child.tagName) : []
    }

    if (innerCanvas?.width && innerCanvas?.height) {
      try {
        const context = innerCanvas.getContext("2d")
        const points = [
          [Math.floor(innerCanvas.width / 2), Math.floor(innerCanvas.height / 2)],
          [1, 1],
          [Math.max(innerCanvas.width - 2, 0), 1],
          [1, Math.max(innerCanvas.height - 2, 0)],
          [Math.max(innerCanvas.width - 2, 0), Math.max(innerCanvas.height - 2, 0)]
        ]
        const pixels = points.map(([x, y]) => Array.from(context.getImageData(x, y, 1, 1).data))
        sample.pixelSample = pixels
        sample.nonBlackSamples = pixels.filter(([r, g, b, a]) => a !== 0 && (r !== 0 || g !== 0 || b !== 0)).length
        const gridColors = []
        for (let y = 0; y < 5; y += 1) {
          for (let x = 0; x < 5; x += 1) {
            const px = Math.floor(((x + 0.5) * innerCanvas.width) / 5)
            const py = Math.floor(((y + 0.5) * innerCanvas.height) / 5)
            gridColors.push(Array.from(context.getImageData(px, py, 1, 1).data).slice(0, 3).join(","))
          }
        }
        sample.uniqueGridColors = Array.from(new Set(gridColors)).slice(0, 12)
        sample.uniqueGridColorCount = new Set(gridColors).size
      } catch (error) {
        sample.pixelError = error.message
      }
    }

    // #region agent log
    agentDebugLog("initial", "H21,H23", "embedded_emulator.js:vnc:canvas_sample", "sampled noVNC canvas pixels and DOM", sample)
    // #endregion
  }

  connectPhone() {
    if (this.destroyed || !this.session?.backend_enabled) return
    const oldPhoneSocket = this.phoneSocket
    this.phoneBridgeActive = true
    const socket = new WebSocket(websocketURL(this.session.phone_path))
    this.phoneSocket = socket
    if (oldPhoneSocket) oldPhoneSocket.close()
    socket.binaryType = "arraybuffer"
    socket.addEventListener("message", event => {
      if (this.destroyed || socket !== this.phoneSocket) return
      this.handlePhoneMessage(event)
    })
    socket.addEventListener("open", () => {
      if (this.destroyed || socket !== this.phoneSocket) return
      this.phoneOpenedAt = Date.now()
      this.phoneBridgeReady = true
      this.appendLog("phone websocket open")
      if (this.buttonState !== 0) this.sendQemu(QEMU.button, [this.buttonState])
    })
    socket.addEventListener("error", () => {
      if (this.destroyed || socket !== this.phoneSocket) return
      this.appendLog("phone websocket error")
    })
    socket.addEventListener("close", event => {
      if (this.destroyed || socket !== this.phoneSocket) return
      this.appendLog(`phone websocket closed (code ${event.code || "?"})`)
      this.phoneBridgeActive = false
      this.phoneBridgeReady = false
      if (this.session && !this.stopping && !this.installing && this.phoneOpenedAt > 0) {
        this.endSession("Embedded emulator phone bridge disconnected")
      }
    })
  }

  async install() {
    if (this.installing || !this.installReady()) return
    const installSessionId = this.session.id
    this.installing = true
    this.updateControlButtons()

    try {
      await this.installPbwViaNativeInstaller(installSessionId)
      if (this.session?.id !== installSessionId) return
      if (this.session?.backend_enabled) {
        try {
          await this.ensurePhoneBridge()
          if (this.session?.id !== installSessionId) return
          this.enableAppLogs()
        } catch (error) {
          if (this.session?.id === installSessionId) {
            this.appendLog(`phone bridge connect failed: ${error.message}`)
          }
        }
      }
      if (this.session?.has_phone_companion && this.session?.backend_enabled && this.session?.artifact_path) {
        try {
          await this.ensurePhoneBridge()
          if (this.session?.id !== installSessionId) return
          await this.installPbwViaPhoneBridge()
        } catch (error) {
          if (this.session?.id === installSessionId) {
            this.appendLog(`phone bridge companion cache refresh failed: ${error.message}`)
          }
        }
      }
    } catch (error) {
      if (this.session?.id === installSessionId && !this.stopping) {
        this.setStatus(`PBW install failed: ${error.message}`)
      }
    } finally {
      if (this.session?.id === installSessionId) {
        this.installing = false
      }
      this.updateControlButtons()
    }
  }

  async installPbwViaNativeInstaller(installSessionId = this.session?.id) {
    if (!this.session?.install_path) {
      this.setStatus("Embedded emulator install API is unavailable.")
      return
    }

    this.setStatus("Installing PBW on embedded emulator via fallback installer...")
    this.appendLog("native PBW install started (this can take a few minutes on large apps)")
    const response = await postJSON(this.session.install_path, {}, {timeoutMs: 300_000})
    if (this.session?.id !== installSessionId) return
    const parts = response.result?.parts?.map(part => part.kind).join(", ")
    this.appInstalled = true
    this.lastSentWeatherJson = null
    this.setStatus(parts ? `PBW installed on embedded emulator (${parts})` : "PBW installed on embedded emulator")
    this.appendLog("native PBW install complete")
    if (this.rfb) {
      this.scheduleVncViewportConfig(this.rfb, "after_install", 500)
      this.scheduleVncViewportConfig(this.rfb, "after_install_2s", 2000)
    }
  }

  async ensurePhoneBridge(timeoutMs = 35_000) {
    if (!this.session?.backend_enabled) return false
    if (this.phoneSocket?.readyState !== WebSocket.OPEN) {
      this.connectPhone()
      await this.waitForPhoneBridge(timeoutMs)
    }
    return true
  }

  waitForPhoneBridge(timeoutMs = 35_000) {
    if (this.phoneSocket?.readyState === WebSocket.OPEN) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const startedAt = Date.now()
      let lastReconnectAt = 0
      const check = () => {
        if (!this.session) {
          reject(new Error("Emulator session ended before phone bridge opened"))
        } else if (this.phoneSocket?.readyState === WebSocket.OPEN) {
          resolve()
        } else if (Date.now() - startedAt >= timeoutMs) {
          reject(new Error("Timed out waiting for phone bridge"))
        } else {
          const state = this.phoneSocket?.readyState
          if ((state === WebSocket.CLOSED || state === WebSocket.CLOSING) && Date.now() - lastReconnectAt >= 400) {
            lastReconnectAt = Date.now()
            this.connectPhone()
          }
          window.setTimeout(check, 100)
        }
      }

      check()
    })
  }

  async loadCompanionPreferences() {
    if (!this.companionPreferencesReady()) {
      this.setStatus("This companion app does not declare preferences or configuration.")
      return
    }
    if (!this.phoneSocket || this.phoneSocket.readyState !== WebSocket.OPEN) {
      this.setStatus("Phone bridge is not ready for companion preferences.")
      return
    }

    this.phoneSocket.send(new Uint8Array([0x0a, 0x01]))
    this.setStatus("Requested companion configuration from phone bridge")
  }

  async handlePhoneMessage(event) {
    const data = new Uint8Array(await this.messageBytes(event.data))
    if (data.length === 0) return

    this.logPhoneBridgeFrame(data)

    switch (data[0]) {
      case 0x00:
        this.appendPebbleFrameLog("watch -> phone", data.slice(1))
        break
      case 0x01:
        this.appendPebbleFrameLog("phone -> watch", data.slice(1))
        break
      case 0x02:
        this.appendLog(this.compactPhoneLog(new TextDecoder().decode(data.slice(1))))
        break
      case 0x05:
        if (this.pendingPypkjsInstall) {
          this.finishPypkjsInstall(data[data.length - 1] === 0)
          this.setStatus(data[data.length - 1] === 0 ? "Phone companion refreshed" : "Phone companion refresh failed")
        }
        break
      case 0x08:
        this.appendLog(data[1] === 0xff ? "phone bridge connected to watch" : "phone bridge disconnected")
        if (data[1] === 0xff && this.appInstalled) this.enableAppLogs()
        break
      case 0x09:
        this.appendLog(data[1] === 0 ? "phone bridge authenticated" : "phone bridge authentication failed")
        if (data[1] === 0 && this.appInstalled) this.enableAppLogs()
        if (data[1] === 0) this.sendSimulatorSettingsToPhoneBridge()
        break
      case 0x0a:
        this.handleConfigFrame(data)
        break
      case 0x0d:
        if (this.weatherDebugAckTimer != null) {
          window.clearTimeout(this.weatherDebugAckTimer)
          this.weatherDebugAckTimer = null
        }
        if (data[1] === 0) {
          if (this.pendingWeatherRetry) {
            const weather = this.pendingWeatherRetry
            this.appendLog(
              `weather trace [browser_inject_ack]: ${this.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
            )
            this.lastSentWeatherJson = JSON.stringify({
              temperatureC: this.parseSimulatorTemperatureC(weather.temperatureC),
              condition: weather.condition || "clear"
            })
            this.pendingWeatherRetry = null
          }
          this.weatherDebugInFlight = false
          this.drainWeatherDebugQueue()
        } else {
          this.appendLog("debug AppMessage to watch failed; retrying weather push")
          this.lastSentWeatherJson = null
          this.weatherDebugInFlight = false
          if (this.pendingWeatherRetry) {
            const weather = this.pendingWeatherRetry
            const timerId = window.setTimeout(() => {
              this.weatherPushRetryTimers = this.weatherPushRetryTimers.filter(id => id !== timerId)
              this.enqueueWeatherDebugPush(weather, {quiet: true, force: true})
            }, 800)
            this.weatherPushRetryTimers.push(timerId)
          } else {
            this.drainWeatherDebugQueue()
          }
        }
        break
      case 0x0e:
        if (data[1] === 0) {
          if (this.simulatorWeatherEnabled()) {
            const weather = this.resolveWeatherSimulatorSettings()
            this.appendLog(
              `weather trace [browser_ack]: ${this.parseSimulatorTemperatureC(weather?.temperatureC) ?? "?"}°C ${weather?.condition || "clear"}`
            )
          }
        } else {
          this.appendLog("simulator settings sync failed")
          if (this.simulatorWeatherEnabled()) {
            this.scheduleWeatherPush({quiet: true})
          }
        }
        break
      case 0x0f:
        this.logWeatherTrace(data.slice(1))
        break
      default:
        this.appendLog(`phone frame ${data.byteLength} bytes`)
        break
    }
  }

  logPhoneBridgeFrame(data) {
    const opcode = data[0]

    if (opcode === 0x02) {
      const text = new TextDecoder().decode(data.slice(1))
      if (/watch -> Elm companion|Elm companion|AppMessage|not responding|error|failed/i.test(text)) {
        // #region agent log
        agentDebugLog("initial", "H31,H32", "embedded_emulator.js:phone:text", "phone bridge text frame", {
          sessionId: this.session?.id,
          text: this.truncate(text, 600)
        })
        // #endregion
      }
      return
    }

    if ((opcode === 0x00 || opcode === 0x01) && data.length >= 5) {
      const frame = data.slice(1)
      const view = new DataView(frame.buffer, frame.byteOffset, frame.byteLength)
      const length = view.getUint16(0, false)
      const endpoint = view.getUint16(2, false)
      if (endpoint === 0x0030 || endpoint === 0x0034 || endpoint === ENDPOINT_APP_LOG || endpoint === ENDPOINT_DATA_LOGGING) {
        const payload = frame.slice(4)
        if (endpoint === 0x0034 && opcode === 0x00 && payload[0] === 0x01) {
          if (this.rfb) this.scheduleVncViewportConfig(this.rfb, "app_start", 500)
          this.scheduleVncCanvasSample("after_app_start_250ms", 250)
          this.scheduleVncCanvasSample("after_app_start_1500ms", 1500)
          this.scheduleWeatherSimulatorInject("after_app_start")
        }
        if (endpoint === 0x0030 && opcode === 0x01) {
          this.scheduleVncCanvasSample("after_phone_appmessage_250ms", 250)
          this.scheduleVncCanvasSample("after_phone_appmessage_1500ms", 1500)
        }
        // #region agent log
        agentDebugLog("initial", "H31,H32,H33,H46", "embedded_emulator.js:phone:pebble_frame", "selected Pebble frame via phone bridge", {
          sessionId: this.session?.id,
          direction: opcode === 0x00 ? "watch_to_phone" : "phone_to_watch",
          endpoint,
          endpointName: this.endpointName(endpoint),
          payloadBytes: length,
          payloadPrefix: this.hexPreview(payload, 80),
          appLog: endpoint === ENDPOINT_APP_LOG ? this.describeAppLogFrame(opcode === 0x00 ? "watch -> phone" : "phone -> watch", payload) : null,
          dataLogging: endpoint === ENDPOINT_DATA_LOGGING ? this.describeDataLoggingPayload(payload) : null
        })
        // #endregion
        if (endpoint === ENDPOINT_DATA_LOGGING) {
          this.recordDataLogEntry(this.describeDataLoggingPayload(payload))
        }
      }
    }
  }

  async messageBytes(data) {
    if (data instanceof ArrayBuffer) return data
    if (data instanceof Blob) return data.arrayBuffer()
    if (typeof data === "string") return new TextEncoder().encode(data).buffer
    return new ArrayBuffer(0)
  }

  pressButton(name, down) {
    if (!(name in BUTTONS)) return
    const bit = 1 << BUTTONS[name]
    this.buttonState = down ? (this.buttonState | bit) : (this.buttonState & ~bit)
    this.sendQemu(QEMU.button, [this.buttonState])
  }

  bindControl(element, eventName, handler) {
    if (!element || this.boundControlElements.has(element)) return
    this.boundControlElements.add(element)
    element.addEventListener(eventName, handler)
  }

  bindControlButtons() {
    this.launchButton = this.el.querySelector("[data-emulator-launch]")
    this.installButton = this.el.querySelector("[data-emulator-install]")
    this.preferencesButton = this.el.querySelector("[data-emulator-preferences]")
    this.screenshotButton = this.el.querySelector("[data-emulator-screenshot]")
    this.storageResetButton = this.el.querySelector("[data-emulator-storage-reset]")
    this.storageAddButton = this.el.querySelector("[data-emulator-storage-add]")
    this.configPanel = this.el.querySelector("[data-emulator-config-panel]")
    this.configFrame = this.el.querySelector("[data-emulator-config-frame]")

    if (this.configPanel && !this.boundControlElements.has(this.configPanel)) {
      this.boundControlElements.add(this.configPanel)
      this.configPanel.addEventListener("click", event => {
        if (event.target === this.configPanel) this.cancelConfig()
      })
    }

    if (this.configFrame && !this.boundControlElements.has(this.configFrame)) {
      this.boundControlElements.add(this.configFrame)
      this.configFrame.addEventListener("load", () => this.maybeHandleConfigReturn(this.configFrame.contentWindow))
    }
  }

  bindEmulatorButtons() {
    this.el.querySelectorAll("[data-emulator-button]").forEach(button => {
      if (this.boundEmulatorButtons.has(button)) return
      this.boundEmulatorButtons.add(button)

      const name = button.dataset.emulatorButton
      button.addEventListener("pointerdown", event => {
        event.preventDefault()
        button.setPointerCapture?.(event.pointerId)
        this.pressButton(name, true)
      })

      const release = event => {
        if (button.hasPointerCapture?.(event.pointerId)) {
          button.releasePointerCapture(event.pointerId)
        }
        this.pressButton(name, false)
      }

      button.addEventListener("pointerup", release)
      button.addEventListener("pointercancel", release)
      button.addEventListener("lostpointercapture", release)
      button.addEventListener("pointerleave", release)
    })
  }

  releaseAllButtons() {
    if (this.buttonState === 0) return
    this.buttonState = 0
    this.sendQemu(QEMU.button, [0])
  }

  setBattery(percent, charging) {
    this.sendQemu(QEMU.battery, encodeBattery(percent, charging))
  }

  sendAccelSample(x, y, z) {
    this.sendQemu(QEMU.accel, encodeAccel(x, y, z))
  }

  sendCompassSample(settings = this.simulatorSettings || {}) {
    this.sendQemu(QEMU.compass, encodeCompass(settings))
  }

  reapplySimulatorSettingsToQemu(options = {}) {
    if (!this.emulatorSessionActive()) return

    if (!this.simulatorSettings) {
      this.refreshSimulatorSettingsFromDataset()
    }

    const settings = this.simulatorSettings
    if (!settings || typeof settings !== "object") return

    this.applySimulatorSettings(settings, {
      source: options.source || "session_ready",
      quiet: options.quiet ?? true,
      syncCompanion: options.syncCompanion ?? false
    })
  }

  applyInitialSimulatorSettings() {
    const raw = this.el.dataset.emulatorSimulatorSettings
    if (!raw) return

    try {
      this.applySimulatorSettings(JSON.parse(raw), {source: "dataset", syncCompanion: false})
      this.lastAppliedSimulatorSettingsJson = raw
    } catch (_error) {
      this.appendLog("Could not parse initial simulator settings from page")
    }
  }

  parseSimulatorCapabilities() {
    const raw = this.el.dataset.emulatorSimulatorCapabilities
    if (!raw) return new Set()

    try {
      const parsed = JSON.parse(raw)
      return new Set(Array.isArray(parsed) ? parsed : [])
    } catch (_error) {
      return new Set()
    }
  }

  simulatorCapabilities() {
    return this._simulatorCapabilities || (this._simulatorCapabilities = this.parseSimulatorCapabilities())
  }

  simulatorWeatherEnabled() {
    return this.simulatorCapabilities().has("weather")
  }

  refreshSimulatorCapabilities() {
    this._simulatorCapabilities = this.parseSimulatorCapabilities()
  }

  companionSimulatorEnabled() {
    return this.el.dataset.emulatorHasPhoneCompanion === "true"
  }

  emulatorSessionActive() {
    return !!this.session?.id
  }

  shouldSyncCompanionSimulator(options = {}) {
    return (
      this.companionSimulatorEnabled() &&
      this.emulatorSessionActive() &&
      options.syncCompanion !== false
    )
  }

  simulatorSettingsWeatherKey(settings = this.simulatorSettings) {
    return this.weatherDebugQueueKey(this.resolveWeatherSimulatorSettings(settings))
  }

  syncSimulatorSettingsFromDataset() {
    const raw = this.el.dataset.emulatorSimulatorSettings
    if (!raw || raw === this.lastAppliedSimulatorSettingsJson) return

    let incoming
    try {
      incoming = JSON.parse(raw)
    } catch (_error) {
      this.appendLog("Could not parse updated simulator settings from page")
      return
    }

    const incomingWeatherKey = this.simulatorSettingsWeatherKey(incoming)
    const currentWeatherKey = this.simulatorSettingsWeatherKey()

    // LiveView DOM patches can lag behind push_event; don't revert fresher settings.
    if (
      this.simulatorSettingsSource === "push_event" &&
      currentWeatherKey &&
      incomingWeatherKey !== currentWeatherKey
    ) {
      return
    }

    this.applySimulatorSettings(incoming, {source: "dataset"})
    this.lastAppliedSimulatorSettingsJson = raw
  }

  refreshSimulatorSettingsFromDataset() {
    const raw = this.el.dataset.emulatorSimulatorSettings
    if (!raw) return

    try {
      this.simulatorSettings = JSON.parse(raw)
    } catch (_error) {
      this.appendLog("Could not parse simulator settings from page dataset")
    }
  }

  applySimulatorSettings(settings = {}, options = {}) {
    this.simulatorSettings = settings
    this.simulatorSettingsSource = options.source || "push_event"
    this.simulatorSettingsAppliedAt = Date.now()

    if (this.emulatorSessionActive()) {
      applySimulatorSettingsToQemu((protocol, payload) => this.sendQemu(protocol, payload), settings)
    }

    if (this.shouldSyncCompanionSimulator(options)) {
      const quiet = options.quiet ?? options.source === "dataset"
      this.pushSimulatorSettingsToPhoneBridgeNow({quiet})
      if (this.simulatorWeatherEnabled()) {
        this.scheduleWeatherPush({quiet})
      }
    }

    this.lastAppliedSimulatorSettingsJson = JSON.stringify(this.simulatorSettingsPayload(settings))
  }

  simulatorSettingsPayload(settings = this.simulatorSettings) {
    if (!settings || typeof settings !== "object") {
      return this.simulatorWeatherEnabled() ? {weather: {...DEFAULT_SIMULATOR_WEATHER}} : {}
    }

    const payload = {...settings}
    const weather = this.resolveWeatherSimulatorSettings(settings)

    if (weather) {
      payload.weather = weather
    } else {
      delete payload.weather
      delete payload.weather_temperatureC
      delete payload.weather_condition
      delete payload.weather_humidityPercent
      delete payload.weather_pressureHpa
      delete payload.weather_windKph
    }

    return payload
  }

  pushSimulatorSettingsToPhoneBridgeNow(options = {}) {
    if (!this.companionSimulatorEnabled()) return false

    const payload = this.simulatorSettingsPayload()
    const sent = this.sendSimulatorSettingsToPhoneBridge(payload)
    if (sent && options.quiet === false && this.simulatorWeatherEnabled()) {
      const weather = this.resolveWeatherSimulatorSettings(payload)
      this.appendLog(
        `synced simulator weather via phone bridge: ${this.parseSimulatorTemperatureC(weather?.temperatureC) ?? "?"}°C ${weather?.condition || "clear"}`
      )
    }
    return sent
  }

  scheduleWeatherPush(options = {}) {
    if (!this.simulatorWeatherEnabled()) return
    if (!this.shouldSyncCompanionSimulator(options)) return
    this.resetWeatherDebugQueueIfStuck("new settings push")
    this.weatherDebugInFlight = false
    this.pendingWeatherRetry = null
    if (this.weatherDebugAckTimer != null) {
      window.clearTimeout(this.weatherDebugAckTimer)
      this.weatherDebugAckTimer = null
    }

    if (this.weatherPushTimer != null) {
      window.clearTimeout(this.weatherPushTimer)
    }
    if (this.weatherDebugFallbackTimer != null) {
      window.clearTimeout(this.weatherDebugFallbackTimer)
      this.weatherDebugFallbackTimer = null
    }

    this.weatherPushTimer = window.setTimeout(() => {
      this.weatherPushTimer = null
      const weather = this.resolveWeatherSimulatorSettings()
      const bridgeSent = this.pushSimulatorSettingsToPhoneBridgeNow()
      const injectTimerId = window.setTimeout(() => {
        this.weatherPushRetryTimers = this.weatherPushRetryTimers.filter(id => id !== injectTimerId)
        const injected = this.enqueueWeatherDebugPush(weather, {quiet: true, force: true})
        if (!injected && options.quiet === false) {
          this.appendLog(
            `skipped simulator weather inject: ${this.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
          )
        }
      }, 400)
      this.weatherPushRetryTimers.push(injectTimerId)
      this.scheduleWeatherDebugFallback(weather, {quiet: options.quiet !== false})
      if (options.quiet === false) {
        if (bridgeSent) {
          this.appendLog(
            `synced simulator weather via phone bridge: ${this.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
          )
        } else {
          this.appendLog("skipped simulator weather sync: phone bridge is not connected")
        }
      }
    }, 150)
  }

  scheduleWeatherDebugFallback(weather, options = {}) {
    if (this.weatherDebugFallbackTimer != null) {
      window.clearTimeout(this.weatherDebugFallbackTimer)
    }

    this.weatherDebugFallbackTimer = window.setTimeout(() => {
      this.weatherDebugFallbackTimer = null
      const sent = this.enqueueWeatherDebugPush(weather, {quiet: true, force: true})
      if (sent && options.quiet === false) {
        this.appendLog(
          `pushed simulator weather to watch: ${this.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
        )
      }
    }, 1500)
  }

  scheduleWeatherDebugAckTimeout() {
    if (this.weatherDebugAckTimer != null) {
      window.clearTimeout(this.weatherDebugAckTimer)
    }

    this.weatherDebugAckTimer = window.setTimeout(() => {
      this.weatherDebugAckTimer = null
      if (!this.weatherDebugInFlight) return
      this.weatherDebugInFlight = false
      this.drainWeatherDebugQueue()
    }, 2500)
  }

  weatherDebugQueueKey(weather) {
    return JSON.stringify({
      temperatureC: this.parseSimulatorTemperatureC(weather?.temperatureC),
      condition: weather?.condition || "clear"
    })
  }

  enqueueWeatherDebugPush(weather, options = {}) {
    if (!this.simulatorWeatherEnabled()) return false
    if (!this.session?.app_uuid) {
      if (options.quiet === false) {
        this.appendLog("skipped simulator weather: install a PBW on the emulator first")
      }
      return false
    }
    if (!this.phoneSocket || this.phoneSocket.readyState !== WebSocket.OPEN) {
      if (options.quiet === false) {
        this.appendLog("skipped simulator weather: phone bridge is not connected")
      }
      return false
    }

    const resolved = weather && typeof weather === "object" ? weather : DEFAULT_SIMULATOR_WEATHER
    const queueKey = this.weatherDebugQueueKey(resolved)
    if (!options.force && queueKey === this.lastSentWeatherJson) {
      return false
    }

    this.weatherDebugQueue = this.weatherDebugQueue.filter(item => item.queueKey !== queueKey)
    this.weatherDebugQueue.push({weather: resolved, options, queueKey})
    return this.drainWeatherDebugQueue()
  }

  drainWeatherDebugQueue() {
    if (this.weatherDebugInFlight || this.weatherDebugQueue.length === 0) {
      return false
    }

    const item = this.weatherDebugQueue.shift()
    this.weatherDebugInFlight = true
    this.weatherDebugInFlightAt = Date.now()
    this.pendingWeatherRetry = item.weather
    const sent = this.pushWeatherDebugAppMessage(item.weather, {quiet: true})
    if (!sent) {
      this.weatherDebugInFlight = false
      this.weatherDebugQueue.unshift(item)
      return false
    }

    this.scheduleWeatherDebugAckTimeout()
    return true
  }

  logWeatherTrace(bytes) {
    try {
      const trace = JSON.parse(new TextDecoder().decode(bytes))
      const temp = trace.temperatureC ?? trace.weather?.temperatureC ?? "?"
      const condition = trace.condition ?? trace.weather?.condition ?? "clear"
      const detail = trace.detail ? ` (${trace.detail})` : ""
      this.appendLog(`weather trace [${trace.stage}]: ${temp}°C ${condition}${detail}`)
    } catch (_error) {
      this.appendLog("weather trace: could not decode trace frame")
    }
  }

  resetWeatherDebugQueueIfStuck(reason) {
    if (!this.weatherDebugInFlight) return false
    const ageMs = Date.now() - this.weatherDebugInFlightAt
    if (ageMs < 2500) return false
    this.weatherDebugInFlight = false
    this.pendingWeatherRetry = null
    if (this.weatherDebugAckTimer != null) {
      window.clearTimeout(this.weatherDebugAckTimer)
      this.weatherDebugAckTimer = null
    }
    this.appendLog(`weather trace [queue_reset]: prior inject ack timed out (${reason}, ${ageMs}ms)`)
    return true
  }

  weatherConditionWireCode(condition) {
    const normalized = String(condition || "clear").toLowerCase().replace(/[^a-z0-9]+/g, "")
    return WEATHER_CONDITION_WIRE_CODES[normalized] || WEATHER_CONDITION_WIRE_CODES.clear
  }

  parseSimulatorTemperatureC(value) {
    if (value === null || value === undefined || value === "") return null
    const parsed = Number(value)
    return Number.isFinite(parsed) ? Math.round(parsed) : null
  }

  resolveWeatherSimulatorSettings(settings = this.simulatorSettings) {
    if (!settings || typeof settings !== "object") {
      return this.simulatorWeatherEnabled() ? DEFAULT_SIMULATOR_WEATHER : null
    }

    const nested = settings.weather
    if (nested && typeof nested === "object" && !Array.isArray(nested)) {
      return {
        temperatureC: nested.temperatureC ?? settings.weather_temperatureC ?? DEFAULT_SIMULATOR_WEATHER.temperatureC,
        condition: nested.condition ?? settings.weather_condition ?? DEFAULT_SIMULATOR_WEATHER.condition,
        humidityPercent: nested.humidityPercent ?? settings.weather_humidityPercent ?? DEFAULT_SIMULATOR_WEATHER.humidityPercent,
        pressureHpa: nested.pressureHpa ?? settings.weather_pressureHpa ?? DEFAULT_SIMULATOR_WEATHER.pressureHpa,
        windKph: nested.windKph ?? settings.weather_windKph ?? DEFAULT_SIMULATOR_WEATHER.windKph
      }
    }

    if (
      settings.weather_temperatureC != null ||
      settings.weather_condition != null ||
      settings.weather_humidityPercent != null ||
      settings.weather_pressureHpa != null ||
      settings.weather_windKph != null
    ) {
      return {
        temperatureC: settings.weather_temperatureC ?? DEFAULT_SIMULATOR_WEATHER.temperatureC,
        condition: settings.weather_condition || DEFAULT_SIMULATOR_WEATHER.condition,
        humidityPercent: settings.weather_humidityPercent ?? DEFAULT_SIMULATOR_WEATHER.humidityPercent,
        pressureHpa: settings.weather_pressureHpa ?? DEFAULT_SIMULATOR_WEATHER.pressureHpa,
        windKph: settings.weather_windKph ?? DEFAULT_SIMULATOR_WEATHER.windKph
      }
    }

    return this.simulatorWeatherEnabled() ? DEFAULT_SIMULATOR_WEATHER : null
  }

  scheduleWeatherSimulatorInject(reason) {
    if (!this.simulatorWeatherEnabled()) return
    this.weatherInjectTimers.forEach(timerId => window.clearTimeout(timerId))
    const timerId = window.setTimeout(() => {
      this.weatherInjectTimers = this.weatherInjectTimers.filter(id => id !== timerId)
      this.injectWeatherSimulatorSettings(reason)
    }, 2000)
    this.weatherInjectTimers = [timerId]
  }

  injectWeatherSimulatorSettings(reason) {
    if (!this.simulatorWeatherEnabled()) return
    const weather = this.resolveWeatherSimulatorSettings()
    const sent = this.pushWeatherDebugAppMessage(weather, {quiet: true})
    if (sent) {
      this.appendLog(
        `injected simulator weather (${reason}): ${this.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
      )
    }
  }

  pushWeatherDebugAppMessage(weather, options = {}) {
    if (!this.simulatorWeatherEnabled()) return false
    const resolved = weather && typeof weather === "object" ? weather : DEFAULT_SIMULATOR_WEATHER
    const temperatureC = this.parseSimulatorTemperatureC(resolved.temperatureC)
    const conditionWire = this.weatherConditionWireCode(resolved.condition)
    const entries = []

    if (temperatureC != null) {
      entries.push({key: DEBUG_SIMULATOR.weatherTemperatureC, type: "int", value: temperatureC})
    }
    entries.push({key: DEBUG_SIMULATOR.weatherConditionWire, type: "int", value: conditionWire})

    return this.sendDebugAppMessage(entries, options)
  }

  sendWeatherSimulatorSettings(weather, options = {}) {
    return this.enqueueWeatherDebugPush(weather, options)
  }

  sendSimulatorSettingsToPhoneBridge(settings = null) {
    const payload = settings ?? this.simulatorSettingsPayload()
    if (!payload) return false
    if (!this.phoneSocket || this.phoneSocket.readyState !== WebSocket.OPEN) return false

    const encoded = new TextEncoder().encode(JSON.stringify(payload))
    const out = new Uint8Array(1 + encoded.length)
    out[0] = 0x0e
    out.set(encoded, 1)
    this.phoneSocket.send(out)
    return true
  }

  sendQemu(protocol, payload) {
    if (!this.session?.id) return
    postJSON(`/api/emulator/${encodeURIComponent(this.session.id)}/control`, {protocol, payload})
      .catch(error => this.appendLog(`embedded control failed: ${error.message}`))
  }

  sendPebbleFrame(endpoint, payload) {
    if (!this.phoneSocket || this.phoneSocket.readyState !== WebSocket.OPEN) return false
    const frame = new Uint8Array(5 + payload.length)
    const view = new DataView(frame.buffer)
    frame[0] = 0x01
    view.setUint16(1, payload.length, false)
    view.setUint16(3, endpoint, false)
    frame.set(payload, 5)
    this.phoneSocket.send(frame)
    return true
  }

  enableAppLogs() {
    const sent = this.sendPebbleFrame(ENDPOINT_APP_LOG, new Uint8Array([1]))
    if (sent) {
      this.appendLog("requested watch AppLog shipping")
      window.setTimeout(() => this.requestStorageSnapshot(), 250)
    } else {
      this.appendLog("skipped watch AppLog shipping: phone bridge is not connected")
    }
  }

  requestStorageSnapshot() {
    if (!this.sendDebugAppMessage([{key: DEBUG_STORAGE.op, type: "uint", value: DEBUG_STORAGE.opSnapshot}], {quiet: true})) {
      return
    }
    this.appendLog("requested watch storage snapshot")
  }

  phoneBridgeSimulatorSettings() {
    return this.simulatorSettingsPayload()
  }

  async installPbwViaPhoneBridge() {
    if (!this.session?.artifact_path) return
    if (!this.phoneSocket || this.phoneSocket.readyState !== WebSocket.OPEN) {
      this.appendLog("skipped phone bridge PBW install: phone websocket is not open")
      return
    }

    this.setStatus("Refreshing phone companion from PBW...")
    this.refreshSimulatorSettingsFromDataset()
    const response = await fetch(this.session.artifact_path)
    if (!response.ok) throw new Error(`Could not fetch PBW for phone bridge: ${response.statusText}`)

    const pbw = new Uint8Array(await response.arrayBuffer())
    const settingsJson = new TextEncoder().encode(JSON.stringify(this.phoneBridgeSimulatorSettings()))
    const payload = new Uint8Array(1 + 1 + 4 + settingsJson.length + pbw.length)
    const view = new DataView(payload.buffer)
    payload[0] = 0x04
    payload[1] = 0x01
    view.setUint32(2, settingsJson.length, false)
    payload.set(settingsJson, 6)
    payload.set(pbw, 6 + settingsJson.length)

    const result = this.waitForPypkjsInstall()
    this.phoneSocket.send(payload)
    this.appendLog(`sent PBW to phone bridge companion cache (${pbw.length} bytes, settings ${settingsJson.length} bytes)`)
    await result
    this.appendLog("phone bridge companion cache refresh complete")
    this.sendSimulatorSettingsToPhoneBridge()
  }

  waitForPypkjsInstall() {
    if (this.pendingPypkjsInstall) return this.pendingPypkjsInstall.promise

    let pending
    const promise = new Promise((resolve, reject) => {
      const timeoutId = window.setTimeout(() => {
        this.pendingPypkjsInstall = null
        reject(new Error("Timed out waiting for phone bridge PBW install"))
      }, PHONE_BRIDGE_INSTALL_TIMEOUT_MS)
      pending = {resolve, reject, timeoutId, promise: null}
      this.pendingPypkjsInstall = pending
    })

    pending.promise = promise
    return promise
  }

  finishPypkjsInstall(success) {
    if (!this.pendingPypkjsInstall) return
    const pending = this.pendingPypkjsInstall
    this.pendingPypkjsInstall = null
    window.clearTimeout(pending.timeoutId)

    if (success) {
      pending.resolve()
    } else {
      pending.reject(new Error("Phone bridge PBW install failed"))
    }
  }

  appendPebbleFrameLog(direction, frame) {
    if (this.pebbleFrameEndpoint(frame) === 0xbeef) {
      this.compactPutBytesFrame()
      return
    }

    if (this.pebbleFrameEndpoint(frame) === ENDPOINT_SYSTEM_LOG) {
      this.compactSystemLogFrame()
      return
    }

    this.flushPutBytesSummary()
    this.flushSystemLogSummary()
    const message = this.describePebbleFrame(direction, frame)
    if (message) this.appendLog(message)
  }

  pebbleFrameEndpoint(frame) {
    if (frame.length < 4) return null
    return new DataView(frame.buffer, frame.byteOffset, frame.byteLength).getUint16(2, false)
  }

  compactPutBytesFrame() {
    this.suppressedPutBytesFrames += 1
    if (this.suppressedPutBytesFrames >= PUTBYTES_SUMMARY_INTERVAL) this.flushPutBytesSummary()
  }

  flushPutBytesSummary() {
    if (this.suppressedPutBytesFrames === 0) return
    const count = this.suppressedPutBytesFrames
    this.suppressedPutBytesFrames = 0
    this.appendLog(`suppressed ${count} PutBytes transfer frame${count === 1 ? "" : "s"}`, {flushTransfers: false})
  }

  compactSystemLogFrame() {
    this.suppressedSystemLogFrames = (this.suppressedSystemLogFrames || 0) + 1
    if (this.suppressedSystemLogFrames >= SYSTEM_LOG_SUMMARY_INTERVAL) this.flushSystemLogSummary()
  }

  flushSystemLogSummary() {
    if (!this.suppressedSystemLogFrames) return
    const count = this.suppressedSystemLogFrames
    this.suppressedSystemLogFrames = 0
    this.appendLog(`suppressed ${count} Pebble system log frame${count === 1 ? "" : "s"}`, {flushSystemLogs: false})
  }

  describePebbleFrame(direction, frame) {
    if (frame.length < 4) return `${direction} Pebble frame (${frame.length} bytes) ${this.hexPreview(frame)}`

    const view = new DataView(frame.buffer, frame.byteOffset, frame.byteLength)
    const length = view.getUint16(0, false)
    const endpoint = view.getUint16(2, false)
    const payload = frame.slice(4)
    const endpointName = this.endpointName(endpoint)

    if (endpoint === 0xbeef && payload[0] === 0x02) return null
    if (endpoint === ENDPOINT_APP_LOG) return this.describeAppLogFrame(direction, payload)

    return `${direction} ${endpointName} endpoint=0x${endpoint.toString(16).padStart(4, "0")} payload=${length} bytes ${this.hexPreview(payload)}`
  }

  describeAppLogFrame(direction, payload) {
    if (payload.length >= 40) {
      const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength)
      const level = this.appLogLevelName(payload[20])
      const messageLength = payload[21]
      const line = view.getUint16(22, false)
      const filename = this.cString(payload.slice(24, 40))
      const message = this.cString(payload.slice(40, 40 + messageLength))
      const source = filename ? `${filename}:${line}` : `line=${line}`
      return `${direction} AppLog ${level} ${source}: ${message || this.hexPreview(payload)}`
    }

    const strings = this.printableStrings(payload)
    const text = strings.length > 0 ? strings.join(" | ") : this.hexPreview(payload)
    return `${direction} AppLog: ${text}`
  }

  describeDataLoggingPayload(payload) {
    if (payload.length < 29) return {payloadPrefix: this.hexPreview(payload)}

    const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength)
    return {
      command: payload[0],
      session: payload[1],
      uuid: this.uuidFromBytes(payload.slice(2, 18)),
      timestamp: view.getUint32(18, true),
      tagHex: `0x${view.getUint32(22, true).toString(16).padStart(8, "0")}`,
      itemType: payload[26],
      itemSize: view.getUint16(27, true)
    }
  }

  uuidFromBytes(bytes) {
    if (bytes.length !== 16) return this.hexPreview(bytes)
    const hex = [...bytes].map(byte => byte.toString(16).padStart(2, "0"))
    return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`
  }

  appLogLevelName(level) {
    switch (level) {
      case 1:
        return "error"
      case 2:
      case 50:
        return "warning"
      case 3:
      case 100:
        return "info"
      case 4:
      case 200:
        return "debug"
      case 5:
      case 255:
        return "verbose"
      default:
        return `level=${level ?? "?"}`
    }
  }

  printableStrings(bytes) {
    const strings = []
    let current = []

    const flush = () => {
      if (current.length >= 2) strings.push(new TextDecoder().decode(new Uint8Array(current)))
      current = []
    }

    for (const byte of bytes) {
      if (byte >= 0x20 && byte <= 0x7e) {
        current.push(byte)
      } else {
        flush()
      }
    }
    flush()

    return strings
  }

  cString(bytes) {
    const end = bytes.indexOf(0)
    const slice = end >= 0 ? bytes.slice(0, end) : bytes
    return new TextDecoder().decode(slice).trim()
  }

  endpointName(endpoint) {
    switch (endpoint) {
      case 0x0030:
        return "AppMessage"
      case 0x0034:
        return "App run state"
      case 0x1771:
        return "App fetch"
      case ENDPOINT_SYSTEM_LOG:
        return "Pebble system log"
      case ENDPOINT_APP_LOG:
        return "AppLog"
      case ENDPOINT_DATA_LOGGING:
        return "Data logging"
      case 0xb1db:
        return "BlobDB"
      case 0xbeef:
        return "PutBytes"
      default:
        return "Pebble frame"
    }
  }

  async waitForPhoneBridgeSettle() {
    const minimumSettleMs = 5000
    const remaining = minimumSettleMs - (Date.now() - this.phoneOpenedAt)
    if (remaining <= 0) return

    this.setStatus("Waiting for phone bridge to settle before install...")
    await new Promise(resolve => window.setTimeout(resolve, remaining))
  }

  handleConfigFrame(data) {
    if (data[1] !== 0x01 || data.length < 6) {
      this.appendLog(`configuration bridge frame ignored: opcode=${data[1] ?? "missing"} bytes=${data.length}`)
      return
    }
    const length = new DataView(data.buffer, data.byteOffset + 2, 4).getUint32(0, false)
    const url = new TextDecoder().decode(data.slice(6, 6 + length))
    this.appendLog(`companion requested configuration URL (${length} bytes)`)
    this.showConfigPage(url)
  }

  showConfigPage(url) {
    this.configUrl = this.withConfigReturnUrl(url)
    if (this.configUrlLabel) {
      this.configUrlLabel.textContent = this.configUrlSummary(this.configUrl)
      this.configUrlLabel.removeAttribute("title")
    }
    this.configPanel?.classList.remove("hidden")
    this.configPanel?.classList.add("flex")
    if (this.configFrame) this.configFrame.src = this.configUrl
    this.configDialog?.focus()
    this.setStatus("Companion configuration requested")
  }

  configUrlSummary(url) {
    if (!url) return ""
    if (url.startsWith("data:text/html")) {
      return `Generated HTML configuration page (${this.formatBytes(url.length)})`
    }

    try {
      const parsed = new URL(url, window.location.href)
      return parsed.origin === "null" ? parsed.href : parsed.toString()
    } catch (_error) {
      return "Companion configuration page"
    }
  }

  compactPhoneLog(message) {
    if (!message) return message
    const configPrefix = "opening companion configuration "
    const configIndex = message.indexOf(configPrefix)
    if (configIndex >= 0) {
      return `${message.slice(0, configIndex)}${configPrefix}${this.configUrlSummary(message.slice(configIndex + configPrefix.length))}`
    }
    return message
  }

  formatBytes(bytes) {
    if (!Number.isFinite(bytes) || bytes < 1024) return `${bytes || 0} bytes`
    const kib = bytes / 1024
    if (kib < 1024) return `${kib.toFixed(kib >= 10 ? 0 : 1)} KiB`
    const mib = kib / 1024
    return `${mib.toFixed(mib >= 10 ? 0 : 1)} MiB`
  }

  withConfigReturnUrl(url) {
    const normalizedUrl = url.startsWith("data:") ? url.replaceAll("#", "%23") : url
    const target = new URL(normalizedUrl, window.location.href)
    target.searchParams.set("return_to", `${window.location.origin}${CONFIG_RETURN_PATH}?`)
    return target.toString()
  }

  maybeHandleConfigReturn(contentWindow) {
    if (!contentWindow) return

    try {
      const location = contentWindow.location
      if (location.origin === window.location.origin && location.pathname === CONFIG_RETURN_PATH) {
        this.completeConfig(location.search.replace(/^\?/, ""))
      }
    } catch (_error) {
      // Cross-origin iframe loads are expected until the config page redirects to return_to.
    }
  }

  completeConfig(query) {
    const response = this.configurationResponseFromQuery(query)
    const bytes = new TextEncoder().encode(response)
    const out = new Uint8Array(6 + bytes.length)
    out[0] = 0x0a
    out[1] = 0x02
    new DataView(out.buffer).setUint32(2, bytes.length, false)
    out.set(bytes, 6)
    if (this.phoneSocket?.readyState === WebSocket.OPEN) {
      this.phoneSocket.send(out)
      this.appendLog(`sent configuration response to phone bridge (${bytes.length} bytes): ${this.truncate(response, 180)}`)
    } else {
      this.appendLog("could not send configuration response: phone bridge websocket is not open")
    }
    this.hideConfigPage()
    this.setStatus("Sent companion configuration response")
  }

  cancelConfig() {
    this.phoneSocket?.send(new Uint8Array([0x0a, 0x03]))
    this.hideConfigPage()
    this.setStatus("Cancelled companion configuration")
  }

  hideConfigPage() {
    this.stopConfigPopupPolling()
    this.configUrl = null
    if (this.configFrame) this.configFrame.removeAttribute("src")
    if (this.configUrlLabel) {
      this.configUrlLabel.textContent = ""
      this.configUrlLabel.removeAttribute("title")
    }
    this.configPanel?.classList.add("hidden")
    this.configPanel?.classList.remove("flex")
  }

  stopConfigPopupPolling() {
    if (this.configPopupTimer) window.clearInterval(this.configPopupTimer)
    this.configPopupTimer = null
  }

  storageKeyFromInput(input) {
    const key = parseInt(input?.value || "", 10)
    return Number.isInteger(key) && key >= 0 ? key : null
  }

  saveNewStorageEntry() {
    const key = this.storageKeyFromInput(this.storageNewKey)
    if (key === null) {
      this.setStatus("Storage key must be a non-negative integer.")
      return
    }
    const type = this.storageNewType?.value === "int" ? "int" : "string"
    const value = this.storageNewValue?.value || ""
    this.saveStorageEntry(key, type, value)
  }

  saveStorageEntry(key, type, value) {
    if (!this.sendDebugStorageWrite(key, type, value)) return
    this.upsertStorageEntry({key, type, value: type === "int" ? String(parseInt(value || "0", 10) || 0) : value})
    this.setStatus(`Saved storage key ${key}`)
  }

  deleteStorageEntry(key) {
    if (!this.sendDebugStorageDelete(key)) return
    this.storageEntries.delete(String(key))
    this.renderStorage()
    this.setStatus(`Deleted storage key ${key}`)
  }

  resetStorage() {
    const keys = Array.from(this.storageEntries.keys())
    if (keys.length === 0) return
    let sent = 0
    keys.forEach(key => {
      if (this.sendDebugStorageDelete(parseInt(key, 10), {quiet: true})) sent += 1
    })
    if (sent > 0) {
      this.storageEntries.clear()
      this.renderStorage()
      this.setStatus(`Reset ${sent} known storage key${sent === 1 ? "" : "s"}`)
    }
  }

  sendDebugStorageWrite(key, type, value) {
    const entries = [
      {key: DEBUG_STORAGE.op, type: "uint", value: DEBUG_STORAGE.opWrite},
      {key: DEBUG_STORAGE.key, type: "uint", value: key},
      {key: DEBUG_STORAGE.type, type: "uint", value: type === "int" ? DEBUG_STORAGE.typeInt : DEBUG_STORAGE.typeString}
    ]
    if (type === "int") {
      entries.push({key: DEBUG_STORAGE.intValue, type: "int", value: parseInt(value || "0", 10) || 0})
    } else {
      entries.push({key: DEBUG_STORAGE.stringValue, type: "string", value})
    }
    return this.sendDebugAppMessage(entries)
  }

  sendDebugStorageDelete(key, options = {}) {
    return this.sendDebugAppMessage(
      [
        {key: DEBUG_STORAGE.op, type: "uint", value: DEBUG_STORAGE.opDelete},
        {key: DEBUG_STORAGE.key, type: "uint", value: key}
      ],
      options
    )
  }

  sendDebugAppMessage(entries, options = {}) {
    if (!this.session?.app_uuid) {
      if (!options.quiet) this.setStatus("Storage editing needs a launched PBW with an app UUID.")
      return false
    }
    if (!this.phoneSocket || this.phoneSocket.readyState !== WebSocket.OPEN) {
      if (!options.quiet) this.setStatus("Phone bridge is not ready for storage editing.")
      return false
    }

    const payload = new TextEncoder().encode(JSON.stringify({uuid: this.session.app_uuid, entries}))
    const out = new Uint8Array(1 + payload.length)
    out[0] = 0x0d
    out.set(payload, 1)
    this.phoneSocket.send(out)
    return true
  }

  upsertStorageEntry(entry) {
    this.storageEntries.set(String(entry.key), {
      key: entry.key,
      type: entry.type || "string",
      value: entry.value ?? "",
      updatedAt: Date.now()
    })
    this.renderStorage()
  }

  storageLogBody(message) {
    if (typeof message !== "string") return ""
    const appLog = message.match(/AppLog(?:\s+\S+)*\s+[^:]+:\s*(.+)$/)
    return appLog ? appLog[1] : message
  }

  observeStorageLog(message) {
    const body = this.storageLogBody(message)
    const match = body.match(/(?:cmd|debug) storage_(read|write)(?:_string)? key=(\d+)(?: value=(.*?)(?:\s+status=|\s+rc=|$))?/)
    if (match) {
      const operation = match[1]
      const key = parseInt(match[2], 10)
      const stringLike = body.includes("storage_read_string") || body.includes("storage_write_string")
      const value = typeof match[3] === "string" ? match[3] : ""
      this.upsertStorageEntry({key, type: stringLike ? "string" : "int", value})
      return
    }

    const deleted = body.match(/(?:cmd|debug) storage_delete key=(\d+)/)
    if (deleted) {
      this.storageEntries.delete(deleted[1])
      this.renderStorage()
    }
  }

  renderStorage() {
    if (!this.storageRows) return
    const entries = Array.from(this.storageEntries.values()).sort((a, b) => a.key - b.key)
    if (entries.length === 0) {
      this.storageRows.innerHTML = `<tr data-emulator-storage-empty><td colspan="4" class="py-3 text-zinc-500">No storage keys observed yet. Launch the app or add a test key below.</td></tr>`
      this.updateControlButtons()
      return
    }

    this.storageRows.replaceChildren(...entries.map(entry => this.storageRow(entry)))
    this.updateControlButtons()
  }

  recordDataLogEntry(entry) {
    if (!entry || entry.payloadPrefix) return
    this.dataLogEntries = [{...entry, recordedAt: Date.now()}, ...this.dataLogEntries].slice(0, 50)
    this.renderDataLog()
  }

  renderDataLog() {
    if (!this.dataLogRows) {
      this.dataLogRows = this.el.querySelector("[data-emulator-data-log-rows]")
    }
    if (!this.dataLogRows) return

    if (this.dataLogEntries.length === 0) {
      this.dataLogRows.innerHTML = `<tr data-emulator-data-log-empty><td colspan="3" class="px-2 py-2 text-zinc-500">No data logging frames yet.</td></tr>`
      return
    }

    this.dataLogRows.replaceChildren(...this.dataLogEntries.map(entry => this.dataLogRow(entry)))
  }

  dataLogRow(entry) {
    const row = document.createElement("tr")
    row.className = "border-b border-zinc-100 last:border-0"
    row.innerHTML = `
      <td class="px-2 py-1 font-mono text-zinc-800"></td>
      <td class="px-2 py-1 text-zinc-700"></td>
      <td class="px-2 py-1 text-zinc-700"></td>
    `
    row.children[0].textContent = entry.tagHex || "—"
    row.children[1].textContent = String(entry.itemType ?? "—")
    row.children[2].textContent = String(entry.itemSize ?? "—")
    return row
  }

  storageRow(entry) {
    const row = document.createElement("tr")
    row.className = "border-b border-zinc-100 last:border-0"
    row.innerHTML = `
      <td class="py-2 pr-2 font-mono text-zinc-800"></td>
      <td class="py-2 pr-2"></td>
      <td class="py-2 pr-2"></td>
      <td class="py-2 text-right"></td>
    `
    row.children[0].textContent = String(entry.key)

    const type = document.createElement("select")
    type.className = "ide-select min-w-[5.5rem] w-full rounded border border-zinc-300 bg-white py-1 pl-2 text-xs"
    type.innerHTML = `<option value="string">String</option><option value="int">Int</option>`
    type.value = entry.type
    row.children[1].append(type)

    const value = document.createElement("input")
    value.type = "text"
    value.value = entry.value
    value.className = "w-full rounded border border-zinc-300 px-2 py-1 text-xs"
    row.children[2].append(value)

    const save = document.createElement("button")
    save.type = "button"
    save.className = "rounded bg-zinc-900 px-2 py-1 text-[11px] font-semibold text-white hover:bg-zinc-700 disabled:cursor-not-allowed disabled:opacity-50"
    save.textContent = "Save"
    save.addEventListener("click", () => this.saveStorageEntry(entry.key, type.value, value.value))

    const del = document.createElement("button")
    del.type = "button"
    del.className = "ml-2 rounded bg-rose-100 px-2 py-1 text-[11px] font-semibold text-rose-800 hover:bg-rose-200 disabled:cursor-not-allowed disabled:opacity-50"
    del.textContent = "Delete"
    del.addEventListener("click", () => this.deleteStorageEntry(entry.key))

    row.children[3].append(save, del)
    return row
  }

  async copyFeedbackReport() {
    const lines = [
      "# Elm Pebble embedded emulator — feedback report",
      "",
      `Generated: ${new Date().toISOString()}`,
      `UI build: ${EMBEDDED_EMULATOR_UI_BUILD}`,
      "",
      "## Environment",
      `Page: ${window.location.href}`,
      `User agent: ${navigator.userAgent}`,
      `Secure context: ${window.isSecureContext}`,
      `Viewport: ${window.innerWidth}x${window.innerHeight}`,
      "",
      "## Project",
      `Slug: ${this.el.dataset.projectSlug || "(missing)"}`,
      `Platform: ${this.el.dataset.emulatorTarget || "(missing)"}`,
      `Screen (page): ${this.el.dataset.emulatorScreenWidth || "?"}x${this.el.dataset.emulatorScreenHeight || "?"}`,
      `Phone companion in project: ${this.el.dataset.emulatorHasPhoneCompanion || "?"}`,
      "",
      "## Runtime dependencies (IDE check)",
      this.formatInstallationStatus(),
      "",
      "## Client state",
      this.formatClientState(),
      ""
    ]

    if (this.session?.ping_path) {
      lines.push("## Session (live ping)")
      try {
        const info = await postJSON(this.session.ping_path)
        lines.push(JSON.stringify(this.redactSession(info), null, 2))
      } catch (error) {
        lines.push(`Ping failed: ${error.message}`)
      }
      lines.push("")
    } else if (this.session) {
      lines.push("## Session (from launch; ping unavailable)")
      lines.push(JSON.stringify(this.redactSession(this.session), null, 2))
      lines.push("")
    } else {
      lines.push("## Session")
      lines.push("(no active session)")
      lines.push("")
    }

    lines.push("## Event log (oldest first)")
    lines.push(this.logLines.length > 0 ? [...this.logLines].reverse().join("\n") : "(empty)")
    lines.push("")
    lines.push("---")
    lines.push("Paste this report when filing feedback or a bug report.")

    const text = lines.join("\n")

    try {
      await navigator.clipboard.writeText(text)
      if (this.status) this.status.textContent = "Copied emulator feedback report to clipboard"
      this.appendLog("Copied emulator feedback report to clipboard", {
        flushTransfers: false,
        flushSystemLogs: false
      })
    } catch (error) {
      this.setStatus(`Could not copy feedback report: ${error.message}`)
    }
  }

  formatInstallationStatus() {
    const raw = this.el.dataset.emulatorInstallationStatus
    if (!raw) return "(installation status not available on page)"

    try {
      const status = JSON.parse(raw)
      const lines = [`Status: ${status.status ?? "unknown"}`, `Platform: ${status.platform ?? "?"}`]

      if (status.error) lines.push(`Error: ${status.error}`)

      if (Array.isArray(status.missing) && status.missing.length > 0) {
        lines.push("Missing:")
        for (const item of status.missing) {
          const label = item?.label || item?.id || JSON.stringify(item)
          const detail = item?.detail ? ` (${item.detail})` : ""
          lines.push(`  - ${label}${detail}`)
        }
      } else if (status.status === "ok") {
        lines.push("All checked dependencies present.")
      }

      if (Array.isArray(status.components) && status.components.length > 0) {
        lines.push("Components:")
        for (const component of status.components) {
          const label = component?.label || component?.id || "component"
          lines.push(`  - ${label}: ${component?.status ?? "?"} — ${component?.detail ?? ""}`)
        }
      }

      return lines.join("\n")
    } catch (_error) {
      return `(could not parse installation status JSON: ${raw.slice(0, 200)})`
    }
  }

  formatVncSessionProbeState() {
    const probe = this.vncSessionProbe
    if (!probe) return "(none)"
    if (!probe.ok) return `failed in ${probe.ms}ms (${probe.error})`
    return `ok in ${probe.ms}ms (alive=${probe.alive}, display_ready=${probe.display_ready})`
  }

  formatVncWebSocketState() {
    const diag = this.vncWsDiag
    if (!diag) return "(none)"
    const state = diag.readyStateLabel || "unknown"
    if (diag.open) {
      return `${state}, ${diag.bytesReceived} bytes in ${diag.framesReceived} frame(s)`
    }
    if (diag.closed) {
      return `${state} (code ${diag.closeCode ?? "?"}, reason ${diag.closeReason || "(none)"})`
    }
    if (diag.error) return `${diag.error} (${state})`
    return state
  }

  formatClientState() {
    const screen = this.expectedScreenSize()
    const vncBacking = this.readVncBackingSize()
    const phoneState =
      this.phoneSocket == null
        ? "none"
        : ["connecting", "open", "closing", "closed"][this.phoneSocket.readyState] || String(this.phoneSocket.readyState)

    return [
      `Status line: ${this.currentStatus || "(none)"}`,
      `Launching: ${this.launching}`,
      `Stopping: ${this.stopping}`,
      `Installing: ${this.installing}`,
      `Session ended: ${this.sessionEnded}`,
      `Session alive (ping): ${this.sessionAlive}`,
      `Display connected: ${this.displayConnected}`,
      `Phone bridge ready: ${this.phoneBridgeReady}`,
      `Phone websocket: ${phoneState}`,
      `VNC connecting: ${this.vncConnecting}`,
      `VNC reconnect attempts: ${this.vncReconnectAttempts}`,
      `VNC transport: ${this.formatVncWebSocketState()}`,
      `VNC session probe: ${this.formatVncSessionProbeState()}`,
      `App installed: ${this.appInstalled}`,
      `Expected screen: ${screen.width}x${screen.height}`,
      `VNC canvas backing: ${vncBacking ? `${vncBacking.width}x${vncBacking.height}` : "(none)"}`,
      `Storage keys: ${this.storageEntries.size}`,
      `Data log entries: ${this.dataLogEntries?.length ?? 0}`
    ].join("\n")
  }

  redactSession(session) {
    if (!session || typeof session !== "object") return session
    const copy = {...session}
    if (copy.token) copy.token = "(redacted)"
    return copy
  }

  async captureScreenshot() {
    if (!this.canvas) return
    const canvas = this.canvas.querySelector("canvas")
    if (!canvas) {
      this.setStatus("No embedded emulator canvas is available yet")
      return
    }

    try {
      this.setStatus("Saving embedded emulator screenshot...")
      const screen = this.expectedScreenSize()
      const image =
        screen &&
        canvas.width >= screen.width &&
        canvas.height >= screen.height &&
        (canvas.width !== screen.width || canvas.height !== screen.height)
          ? this.cropCanvasToScreen(canvas, screen)
          : canvas.toDataURL("image/png")

      const result = await postJSON(`/api/wasm-emulator/projects/${encodeURIComponent(this.el.dataset.projectSlug)}/screenshot`, {
        platform: this.el.dataset.emulatorTarget || "embedded",
        image
      })

      if (result.screenshot) {
        this.hook.pushEvent("wasm-screenshot-saved", {screenshot: result.screenshot})
      }

      this.setStatus("Saved embedded emulator screenshot")
    } catch (error) {
      this.setStatus(`Could not save embedded emulator screenshot: ${error.message}`)
    }
  }

  schedulePingAfterDisplayConnect() {
    this.stopPingAfterDisplayTimer()
    if (!this.session || this.destroyed) return

    const start = () => {
      this.pingAfterDisplayTimer = null
      if (this.session && !this.destroyed) this.startPing()
    }

    if (this.displayConnected) {
      start()
      return
    }

    this.pingAfterDisplayTimer = window.setTimeout(start, 45_000)
  }

  stopPingAfterDisplayTimer() {
    if (this.pingAfterDisplayTimer) window.clearTimeout(this.pingAfterDisplayTimer)
    this.pingAfterDisplayTimer = null
  }

  startPing() {
    this.stopPing()
    if (!this.session || this.destroyed) return
    this.pingSession()
    this.pingTimer = window.setInterval(() => this.pingSession(), 5_000)
  }

  stopPing() {
    if (this.pingTimer) window.clearInterval(this.pingTimer)
    this.pingTimer = null
  }

  async pingSession() {
    const session = this.session
    if (!session || this.destroyed) return

    try {
      const response = await postJSON(session.ping_path)
      if (this.session?.id !== session.id || this.destroyed) return
      if (response?.alive === true) {
        this.sessionAlive = true
      } else if (!this.installing) {
        this.sessionAlive = false
        this.endSession("Embedded emulator is no longer running")
      }
    } catch (_error) {
      if (this.session?.id === session.id && !this.destroyed && !this.installing) {
        this.sessionAlive = false
        this.endSession("Embedded emulator is no longer reachable")
      }
    }
  }

  targetScreenSize() {
    const width = parseInt(this.el.dataset.emulatorScreenWidth || "144", 10)
    const height = parseInt(this.el.dataset.emulatorScreenHeight || "168", 10)
    return {width, height}
  }

  expectedScreenSize() {
    const target = this.targetScreenSize()
    const sessionScreen = this.session?.screen
    if (!sessionScreen?.width || !sessionScreen?.height) return target
    if (sessionScreen.width !== target.width || sessionScreen.height !== target.height) return target
    return {width: sessionScreen.width, height: sessionScreen.height}
  }

  cropCanvasToScreen(canvas, screen) {
    const crop = document.createElement("canvas")
    crop.width = screen.width
    crop.height = screen.height
    const ctx = crop.getContext("2d")
    ctx.imageSmoothingEnabled = false
    ctx.drawImage(canvas, 0, 0, canvas.width, canvas.height, 0, 0, screen.width, screen.height)
    return crop.toDataURL("image/png")
  }

  warnSessionScreenMismatch() {
    const target = this.targetScreenSize()
    const sessionScreen = this.session?.screen
    if (!sessionScreen?.width || !sessionScreen?.height) return
    if (sessionScreen.width === target.width && sessionScreen.height === target.height) return
    this.appendLog(
      `emulator session screen ${sessionScreen.width}x${sessionScreen.height} differs from selected target ${target.width}x${target.height}; using target size for display`
    )
  }

  logEmulatorPlatform() {
    const screen = this.expectedScreenSize()
    const platform = this.session?.platform || this.el.dataset.emulatorTarget || "unknown"
    this.appendLog(`Embedded emulator platform ${platform} (${screen.width}x${screen.height})`)
  }

  applyCanvasSize() {
    this.resizeCanvas(this.expectedScreenSize())
  }

  resizeCanvas(screen) {
    if (!this.canvas || !screen) return
    this.canvas.style.width = `${screen.width}px`
    this.canvas.style.height = `${screen.height}px`
    this.canvas.style.overflow = "hidden"
    this.canvas.style.display = "block"
    this.canvas.style.imageRendering = "pixelated"
    const innerCanvas = this.canvas.querySelector("canvas")
    if (innerCanvas) innerCanvas.style.imageRendering = "pixelated"
  }

  setStatus(message) {
    this.currentStatus = message
    if (this.status) this.status.textContent = message
    this.appendLog(message)
  }

  appendLog(message, options = {}) {
    if (options.flushTransfers !== false) this.flushPutBytesSummary()
    if (options.flushSystemLogs !== false) this.flushSystemLogSummary()
    this.observeStorageLog(message)
    const stamp = `${new Date().toLocaleTimeString()} ${message}`
    const line =
      this.logLines.length === 0 && message.includes("Launching embedded emulator")
        ? `${stamp} [ui ${EMBEDDED_EMULATOR_UI_BUILD}]`
        : stamp
    this.logLines.unshift(line)
    this.logLines = this.logLines.slice(0, MAX_LOG_LINES)
    this.scheduleLogFlush()
    this.notifyStateChanged()
  }

  scheduleLogFlush() {
    if (this.destroyed || !this.log || this.logFlushScheduled) return
    this.logFlushScheduled = true
    window.requestAnimationFrame(() => {
      this.logFlushScheduled = false
      this.renderLog()
    })
  }

  renderLog() {
    if (this.log) this.log.textContent = this.logLines.join("\n").slice(0, MAX_LOG_CHARS)
  }

  clearLog() {
    this.logLines = []
    this.suppressedPutBytesFrames = 0
    this.logFlushScheduled = false
    if (this.log) this.log.textContent = ""
    this.notifyStateChanged()
  }

  endSession(message) {
    if (this.sessionEnded) return
    this.sessionEnded = true
    this.sessionAlive = false
    this.displayConnected = false
    this.phoneBridgeReady = false
    const oldPhoneSocket = this.phoneSocket
    this.session = null
    this.launching = false
    this.stopping = false
    this.installing = false
    this.pendingPypkjsInstall = null
    this.phoneBridgeActive = false
    this.stopPingAfterDisplayTimer()
    this.stopPing()
    this.stopVncReconnect()
    this.stopConfigPopupPolling()
    this.hideConfigPage()
    if (this.rfb) {
      this.reconnectingVnc = true
      this.rfb.disconnect()
      this.rfb = null
    }
    if (oldPhoneSocket) {
      this.phoneSocket = null
      oldPhoneSocket.close()
    }
    this.applyCanvasSize()
    this.setStatus(message)
    this.updateControlButtons()
  }

  configurationResponseFromQuery(query) {
    const params = new URLSearchParams(query || "")
    const response = params.get("response")
    return response === null ? (query || "") : response
  }

  hexPreview(bytes, max = 24) {
    const shown = Array.from(bytes.slice(0, max), byte => byte.toString(16).padStart(2, "0")).join(" ")
    return bytes.length > max ? `${shown} ...` : shown
  }

  truncate(value, max) {
    if (value.length <= max) return value
    return `${value.slice(0, max)}...`
  }

  updateControlButtons() {
    this.launchButton = this.el.querySelector("[data-emulator-launch]")
    this.installButton = this.el.querySelector("[data-emulator-install]")
    this.preferencesButton = this.el.querySelector("[data-emulator-preferences]")
    this.screenshotButton = this.el.querySelector("[data-emulator-screenshot]")
    this.storageResetButton = this.el.querySelector("[data-emulator-storage-reset]")
    this.storageAddButton = this.el.querySelector("[data-emulator-storage-add]")

    const hasSession = !!this.session
    this.setButtonDisabled(this.launchButton, this.launching || this.stopping)
    this.setButtonDisabled(this.installButton, this.launching || this.installing || this.stopping || !this.installReady())
    this.setButtonDisabled(this.preferencesButton, this.launching || this.stopping || !this.companionPreferencesReady())
    this.setButtonDisabled(this.screenshotButton, this.launching || this.stopping || !this.canCaptureScreenshot())
    this.setButtonDisabled(this.storageAddButton, this.launching || this.stopping || !hasSession)
    this.setButtonDisabled(this.storageResetButton, this.launching || this.stopping || !hasSession || this.storageEntries.size === 0)

    if (this.launchButton) this.launchButton.textContent = this.launchButtonLabel()
    if (this.installButton) this.installButton.textContent = this.installing ? "Sending..." : "Send PBW"
  }

  launchButtonLabel() {
    if (this.launching) return "Launching..."
    if (this.stopping) return "Stopping..."
    return this.session ? "Stop" : "Launch"
  }

  installReady() {
    return !!(
      this.session?.backend_enabled &&
      this.session?.install_path &&
      !this.sessionEnded &&
      this.sessionAlive &&
      !this.launching &&
      !this.stopping
    )
  }

  companionPreferencesReady() {
    return !!(this.session?.has_companion_preferences && this.session?.backend_enabled)
  }

  canCaptureScreenshot() {
    return !!this.canvas?.querySelector("canvas")
  }

  setButtonDisabled(button, disabled) {
    if (!button) return
    button.disabled = disabled
    button.setAttribute("aria-disabled", disabled ? "true" : "false")
  }
}
