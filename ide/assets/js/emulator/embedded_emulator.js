const BUTTONS = {back: 0, up: 1, select: 2, down: 3}
const QEMU = {
  tap: 2,
  bluetooth: 3,
  battery: 5,
  button: 8,
  timeFormat: 9,
  timelinePeek: 10,
  accel: 11,
  compass: 12
}
const CONFIG_RETURN_PATH = "/api/emulator/config-return"
const MAX_LOG_LINES = 300
const MAX_LOG_CHARS = 40000
const PUTBYTES_SUMMARY_INTERVAL = 25
const SYSTEM_LOG_SUMMARY_INTERVAL = 50
const PHONE_BRIDGE_INSTALL_TIMEOUT_MS = 120000
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

const csrfToken = () => document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
let rfbModulePromise = null
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

function loadRFB() {
  if (!rfbModulePromise) {
    rfbModulePromise = import("@novnc/novnc").then(module => module.default)
  }

  return rfbModulePromise
}

async function postJSON(url, body = {}) {
  const response = await fetch(url, {
    method: "POST",
    headers: {"content-type": "application/json", "x-csrf-token": csrfToken()},
    body: JSON.stringify(body)
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(data.error || response.statusText)
  return data
}

function websocketURL(path) {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
  return `${protocol}//${window.location.host}${path}`
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
    this.boundEmulatorButtons = new WeakSet()
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
    this.launchButton?.addEventListener("click", () => this.toggleLaunch())
    this.installButton?.addEventListener("click", () => this.install())
    this.preferencesButton?.addEventListener("click", () => this.loadCompanionPreferences())
    this.storageResetButton?.addEventListener("click", () => this.resetStorage())
    this.storageAddButton?.addEventListener("click", () => this.saveNewStorageEntry())
    this.screenshotButton?.addEventListener("click", () => this.captureScreenshot())
    this.el.querySelector("[data-emulator-config-cancel]")?.addEventListener("click", () => this.cancelConfig())
    this.configPanel?.addEventListener("click", event => {
      if (event.target === this.configPanel) this.cancelConfig()
    })
    this.configFrame?.addEventListener("load", () => this.maybeHandleConfigReturn(this.configFrame.contentWindow))
    document.addEventListener("keydown", this.handleConfigKeyDown)

    this.bindEmulatorButtons()

    this.el.querySelector("[data-emulator-tap]")?.addEventListener("click", () => this.sendQemu(QEMU.tap, [0, 1]))
    this.el.querySelector("[data-emulator-compass-send]")?.addEventListener("click", () => this.sendCompassSample())
    this.state.listeners.add(this.syncStateToDom)
    window.addEventListener("focus", this.handlePageVisible)
    document.addEventListener("visibilitychange", this.handlePageVisible)
    this.applyInitialSimulatorSettings()
    this.resumeExistingSession()
    this.applyCanvasSize()
    this.syncStateToDom()
    this.ensureVncAttached()
  }

  updated() {
    const previousCanvas = this.canvas
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

  resumeExistingSession() {
    if (!this.session) return

    this.sessionEnded = false
    this.resizeCanvas(this.session.screen)
    this.startPing()
    if (this.session.backend_enabled && !(this.rfb && this.rfbCanvas === this.canvas)) {
      this.connectVnc().catch(error => {
        if (this.session && !this.stopping && !this.destroyed) {
          this.scheduleVncReconnect(`Embedded emulator display reconnect failed: ${error.message}`)
        }
      })
    }
    if (this.phoneBridgeActive) this.connectPhone()
  }

  destroy(removeListeners = true) {
    this.destroyed = true
    this.state.listeners.delete(this.syncStateToDom)
    this.stopPing()
    this.stopVncReconnect()
    this.stopConfigPopupPolling()
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
    this.releaseAllButtons()
    if (this.rfb) {
      const oldRfb = this.rfb
      this.rfb = null
      this.rfbCanvas = null
      oldRfb.disconnect()
    }
    if (this.phoneSocket) this.phoneSocket.close()
  }

  notifyStateChanged() {
    this.state.listeners.forEach(listener => listener())
  }

  toggleLaunch() {
    if (this.session) {
      this.stop()
    } else {
      this.launch()
    }
  }

  async launch() {
    if (this.launching || this.session) return
    this.launching = true
    this.updateControlButtons()

    try {
      this.clearLog()
      this.hideConfigPage()
      this.sessionEnded = false
      this.appInstalled = false
      this.setStatus("Launching embedded emulator...")
      const payload = {
        slug: this.el.dataset.projectSlug,
        platform: this.el.dataset.emulatorTarget
      }
      this.session = await postJSON("/api/emulator/launch", payload)
      // #region agent log
      agentDebugLog("initial", "H19,H20,H21", "embedded_emulator.js:launch:session", "emulator launch response received in browser", {
        sessionId: this.session?.id,
        backendEnabled: this.session?.backend_enabled,
        vncPath: this.session?.vnc_path,
        screen: this.session?.screen
      })
      // #endregion
      if (!this.destroyed) {
        this.resizeCanvas(this.session.screen)
        await this.connectVnc()
        this.startPing()
      }
      this.setStatus(this.session.backend_enabled ? "Embedded emulator connected" : "Embedded emulator backend disabled; launch API is in dry-run mode")
      if (this.session.backend_enabled) {
        this.ensurePhoneBridge()
          .then(() => {
            if (this.appInstalled) this.enableAppLogs()
          })
          .catch(error => this.appendLog(`phone bridge connect failed: ${error.message}`))
      }
    } catch (error) {
      this.setStatus(`Embedded emulator failed: ${error.message}`)
    } finally {
      this.launching = false
      this.updateControlButtons()
    }
  }

  async stop() {
    if (!this.session || this.stopping) return
    const session = this.session
    this.stopping = true
    this.updateControlButtons()

    try {
      await postJSON(session.kill_path)
      this.endSession("Embedded emulator stopped")
    } catch (error) {
      this.setStatus(`Could not stop embedded emulator: ${error.message}`)
    } finally {
      this.stopping = false
      this.updateControlButtons()
    }
  }

  async connectVnc() {
    if (this.destroyed || !this.session.backend_enabled || !this.canvas) return
    if (this.vncConnecting) return
    this.vncConnecting = true
    if (this.rfb) {
      this.reconnectingVnc = true
      this.rfb.disconnect()
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
    let rfb
    try {
      rfb = new RFB(this.canvas, websocketURL(this.session.vnc_path), {shared: true})
    } catch (error) {
      this.vncConnecting = false
      throw error
    }
    this.rfb = rfb
    this.rfbCanvas = this.canvas
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
    rfb.scaleViewport = true
    rfb.resizeSession = false
    rfb.addEventListener("connect", () => {
      if (this.destroyed) return
      if (rfb !== this.rfb) return
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
      this.scheduleVncCanvasSample("after_connect")
      this.scheduleVncCanvasSample("after_connect_1s", 1000)
      if (this.session && !this.stopping) this.setStatus("Embedded emulator display connected")
    })
    rfb.addEventListener("disconnect", event => {
      if (this.destroyed) return
      if (rfb !== this.rfb) return
      if (this.reconnectingVnc) return
      // #region agent log
      agentDebugLog("initial", "H19,H20", "embedded_emulator.js:vnc:disconnect", "noVNC disconnected", {
        sessionId: this.session?.id,
        clean: event?.detail?.clean,
        reconnecting: this.reconnectingVnc,
        stopping: this.stopping
      })
      // #endregion
      if (this.session && !this.stopping) this.scheduleVncReconnect("Embedded emulator display disconnected; reconnecting...")
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
    this.scheduleVncReconnect("Embedded emulator display unavailable; reconnecting...")
  }

  scheduleVncReconnect(message) {
    if (this.destroyed || !this.session?.backend_enabled || this.stopping || this.vncReconnectTimer) return
    this.setStatus(message)
    const delay = Math.min(500 * 2 ** this.vncReconnectAttempts, 5_000)
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
      this.connectVnc().catch(error => {
        this.reconnectingVnc = false
        if (this.session && !this.stopping && !this.destroyed) this.scheduleVncReconnect(`Embedded emulator display reconnect failed: ${error.message}`)
      })
    }, delay)
  }

  stopVncReconnect() {
    if (this.vncReconnectTimer) window.clearTimeout(this.vncReconnectTimer)
    this.vncReconnectTimer = null
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
    if (this.destroyed || !this.session.backend_enabled) return
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
      this.appendLog("phone websocket open")
      if (this.buttonState !== 0) this.sendQemu(QEMU.button, [this.buttonState])
    })
    socket.addEventListener("close", () => {
      if (this.destroyed || socket !== this.phoneSocket) return
      this.appendLog("phone websocket closed")
      this.phoneBridgeActive = false
      if (this.session && !this.stopping && !this.installing) {
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
    const response = await postJSON(this.session.install_path)
    if (this.session?.id !== installSessionId) return
    const parts = response.result?.parts?.map(part => part.kind).join(", ")
    this.appInstalled = true
    this.lastSentWeatherJson = null
    this.setStatus(parts ? `PBW installed on embedded emulator (${parts})` : "PBW installed on embedded emulator")
    this.appendLog("native PBW install complete")
  }

  async ensurePhoneBridge(timeoutMs = 10_000) {
    if (!this.session?.backend_enabled) return false
    if (this.phoneSocket?.readyState !== WebSocket.OPEN) {
      this.connectPhone()
      await this.waitForPhoneBridge(timeoutMs)
    }
    return true
  }

  waitForPhoneBridge(timeoutMs = 10_000) {
    if (this.phoneSocket?.readyState === WebSocket.OPEN) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const startedAt = Date.now()
      const check = () => {
        if (!this.session) {
          reject(new Error("Emulator session ended before phone bridge opened"))
        } else if (this.phoneSocket?.readyState === WebSocket.OPEN) {
          resolve()
        } else if (Date.now() - startedAt >= timeoutMs) {
          reject(new Error("Timed out waiting for phone bridge"))
        } else {
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
          const weather = this.resolveWeatherSimulatorSettings()
          this.appendLog(
            `weather trace [browser_ack]: ${this.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
          )
        } else {
          this.appendLog("simulator settings sync failed")
          this.scheduleWeatherPush({quiet: true})
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
    this.sendQemu(QEMU.battery, [Math.max(0, Math.min(100, percent || 0)), charging ? 1 : 0])
  }

  signedInt16Bytes(value) {
    const clamped = Math.max(-32768, Math.min(32767, value | 0))
    const unsigned = clamped < 0 ? clamped + 65536 : clamped
    return [(unsigned >> 8) & 0xff, unsigned & 0xff]
  }

  sendAccelSample(x, y, z) {
    const payload = [
      ...this.signedInt16Bytes(x),
      ...this.signedInt16Bytes(y),
      ...this.signedInt16Bytes(z)
    ]
    this.sendQemu(QEMU.accel, payload)
  }

  sendCompassSample(settings = this.simulatorSettings || {}) {
    const degrees = Math.max(0, Math.min(360, Number(settings.compass_heading_deg ?? 0)))
    const valid = settings.compass_valid ? 1 : 0
    const degInt = Math.round(degrees)
    this.sendQemu(QEMU.compass, [(degInt >> 8) & 0xff, degInt & 0xff, valid])
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
      if (settings.battery_percent != null || settings.charging != null) {
        this.setBattery(settings.battery_percent ?? 88, !!settings.charging)
      }

      if (settings.connected != null) {
        this.sendQemu(QEMU.bluetooth, [settings.connected ? 1 : 0])
      }

      if (settings.clock_24h != null) {
        this.sendQemu(QEMU.timeFormat, [settings.clock_24h ? 1 : 0])
      }

      if (settings.timeline_peek != null) {
        this.sendQemu(QEMU.timelinePeek, [settings.timeline_peek ? 1 : 0])
      }

      if (settings.compass_heading_deg != null || settings.compass_valid != null) {
        this.sendCompassSample(settings)
      }
    }

    if (this.shouldSyncCompanionSimulator(options)) {
      const quiet = options.quiet ?? options.source === "dataset"
      this.pushSimulatorSettingsToPhoneBridgeNow({quiet})
      this.scheduleWeatherPush({quiet})
    }

    this.lastAppliedSimulatorSettingsJson = JSON.stringify(this.simulatorSettingsPayload(settings))
  }

  simulatorSettingsPayload(settings = this.simulatorSettings) {
    if (!settings || typeof settings !== "object") {
      return {weather: {...DEFAULT_SIMULATOR_WEATHER}}
    }

    const weather = this.resolveWeatherSimulatorSettings(settings)
    return {...settings, weather}
  }

  pushSimulatorSettingsToPhoneBridgeNow(options = {}) {
    if (!this.companionSimulatorEnabled()) return false

    const payload = this.simulatorSettingsPayload()
    const sent = this.sendSimulatorSettingsToPhoneBridge(payload)
    if (sent && options.quiet === false) {
      const weather = this.resolveWeatherSimulatorSettings(payload)
      this.appendLog(
        `synced simulator weather via phone bridge: ${this.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
      )
    }
    return sent
  }

  scheduleWeatherPush(options = {}) {
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
    if (!settings || typeof settings !== "object") return DEFAULT_SIMULATOR_WEATHER

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

    return DEFAULT_SIMULATOR_WEATHER
  }

  scheduleWeatherSimulatorInject(reason) {
    this.weatherInjectTimers.forEach(timerId => window.clearTimeout(timerId))
    const timerId = window.setTimeout(() => {
      this.weatherInjectTimers = this.weatherInjectTimers.filter(id => id !== timerId)
      this.injectWeatherSimulatorSettings(reason)
    }, 2000)
    this.weatherInjectTimers = [timerId]
  }

  injectWeatherSimulatorSettings(reason) {
    const weather = this.resolveWeatherSimulatorSettings()
    const sent = this.pushWeatherDebugAppMessage(weather, {quiet: true})
    if (sent) {
      this.appendLog(
        `injected simulator weather (${reason}): ${this.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
      )
    }
  }

  pushWeatherDebugAppMessage(weather, options = {}) {
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

  async captureScreenshot() {
    if (!this.canvas) return
    const canvas = this.canvas.querySelector("canvas")
    if (!canvas) {
      this.setStatus("No embedded emulator canvas is available yet")
      return
    }

    try {
      this.setStatus("Saving embedded emulator screenshot...")
      const result = await postJSON(`/api/wasm-emulator/projects/${encodeURIComponent(this.el.dataset.projectSlug)}/screenshot`, {
        platform: this.el.dataset.emulatorTarget || "embedded",
        image: canvas.toDataURL("image/png")
      })

      if (result.screenshot) {
        this.hook.pushEvent("wasm-screenshot-saved", {screenshot: result.screenshot})
      }

      this.setStatus("Saved embedded emulator screenshot")
    } catch (error) {
      this.setStatus(`Could not save embedded emulator screenshot: ${error.message}`)
    }
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
      if (response?.alive === false && !this.installing) {
        this.endSession("Embedded emulator is no longer running")
      }
    } catch (_error) {
      if (this.session?.id === session.id && !this.destroyed && !this.installing) {
        this.endSession("Embedded emulator is no longer reachable")
      }
    }
  }

  targetScreenSize() {
    const width = parseInt(this.el.dataset.emulatorScreenWidth || "144", 10)
    const height = parseInt(this.el.dataset.emulatorScreenHeight || "168", 10)
    return {width, height}
  }

  applyCanvasSize() {
    this.resizeCanvas(this.session?.screen || this.targetScreenSize())
  }

  resizeCanvas(screen) {
    if (!this.canvas || !screen) return
    this.canvas.style.width = `${screen.width}px`
    this.canvas.style.height = `${screen.height}px`
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
    this.logLines.unshift(`${new Date().toLocaleTimeString()} ${message}`)
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
    const oldPhoneSocket = this.phoneSocket
    this.session = null
    this.stopping = false
    this.installing = false
    this.pendingPypkjsInstall = null
    this.phoneBridgeActive = false
    this.stopPing()
    this.stopVncReconnect()
    this.stopConfigPopupPolling()
    this.hideConfigPage()
    if (this.rfb) {
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
    return !!(this.session?.backend_enabled && this.session?.install_path && !this.sessionEnded)
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
