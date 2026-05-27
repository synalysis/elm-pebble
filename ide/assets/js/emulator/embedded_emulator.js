/**
 * Embedded Pebble emulator browser host (QEMU + Phoenix VNC channel).
 *
 * @typedef {Object} EmulatorSessionInfo
 * @property {string} id
 * @property {string} platform
 * @property {string} artifact_path
 * @property {string} install_path
 * @property {string} ping_path
 * @property {string} kill_path
 * @property {string} vnc_path
 * @property {string} phone_path
 * @property {boolean} display_ready
 * @property {boolean} phone_bridge_ready
 * @property {boolean} backend_enabled
 * @property {{width: number, height: number}} screen
 * @property {string[]} controls
 */

import {postJSON, websocketURL} from "./emulator_http.js"
import {EmulatorVnc} from "./emulator_vnc.js"
import {EmulatorSessionClient} from "./emulator_session_client.js"
import {EmulatorSimulatorDelivery} from "./emulator_simulator_delivery.js"
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

const EMBEDDED_EMULATOR_UI_BUILD = "v22-refactor"
const PHOENIX_SOCKET_OPEN_TIMEOUT_MS = 10_000
const VNC_CHANNEL_JOIN_TIMEOUT_MS = 10_000

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
    this.simulatorDelivery = new EmulatorSimulatorDelivery(this)
    this.sessionClient = new EmulatorSessionClient(this)
    this.vnc = new EmulatorVnc(this)
    this.lastQemuSettingsApply = null
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

  validatePersistedSession(...args) {
    return this.sessionClient.validatePersistedSession(...args)
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

  async launch(...args) {
    return this.sessionClient.launch(...args)
  }

  async stop(...args) {
    return this.sessionClient.stop(...args)
  }

  resolveCanvas(...args) { return this.vnc.resolveCanvas(...args) }
  waitForDisplayReady(...args) { return this.vnc.waitForDisplayReady(...args) }
  connectDisplay(...args) { return this.vnc.connectDisplay(...args) }
  closeVncSocket(...args) { return this.vnc.closeVncSocket(...args) }
  closeVncChannel(...args) { return this.vnc.closeVncChannel(...args) }
  disconnectRfb(...args) { return this.vnc.disconnectRfb(...args) }
  ensurePhoenixSocket(...args) { return this.vnc.ensurePhoenixSocket(...args) }
  decodeChannelBinary(...args) { return this.vnc.decodeChannelBinary(...args) }
  base64ToArrayBuffer(...args) { return this.vnc.base64ToArrayBuffer(...args) }
  vncBytes(...args) { return this.vnc.vncBytes(...args) }
  bytesToBase64(...args) { return this.vnc.bytesToBase64(...args) }
  pushVncFrame(...args) { return this.vnc.pushVncFrame(...args) }
  resetVncFramePipeline(...args) { return this.vnc.resetVncFramePipeline(...args) }
  enqueueVncChannelFrame(...args) { return this.vnc.enqueueVncChannelFrame(...args) }
  bindVncFrameSink(...args) { return this.vnc.bindVncFrameSink(...args) }
  deliverVncJoinInitial(...args) { return this.vnc.deliverVncJoinInitial(...args) }
  joinVncChannel(...args) { return this.vnc.joinVncChannel(...args) }
  createVncChannelTransport(...args) { return this.vnc.createVncChannelTransport(...args) }
  resetVncWsDiag(...args) { return this.vnc.resetVncWsDiag(...args) }
  attachVncWebSocketDiagnostics(...args) { return this.vnc.attachVncWebSocketDiagnostics(...args) }
  probeEmulatorSession(...args) { return this.vnc.probeEmulatorSession(...args) }
  openVncWebSocket(...args) { return this.vnc.openVncWebSocket(...args) }
  connectVnc(...args) { return this.vnc.connectVnc(...args) }
  reconnectVncAfterDomPatch(...args) { return this.vnc.reconnectVncAfterDomPatch(...args) }
  ensureVncAttached(...args) { return this.vnc.ensureVncAttached(...args) }
  scheduleVncReconnect(...args) { return this.vnc.scheduleVncReconnect(...args) }
  stopVncReconnect(...args) { return this.vnc.stopVncReconnect(...args) }
  readVncBackingSize(...args) { return this.vnc.readVncBackingSize(...args) }
  readVncFramebufferSize(...args) { return this.vnc.readVncFramebufferSize(...args) }
  scheduleVncViewportConfig(...args) { return this.vnc.scheduleVncViewportConfig(...args) }
  configureVncDisplay(...args) { return this.vnc.configureVncDisplay(...args) }
  scheduleVncCanvasSample(...args) { return this.vnc.scheduleVncCanvasSample(...args) }
  logVncCanvasSample(...args) { return this.vnc.logVncCanvasSample(...args) }
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

  installPbwViaNativeInstaller(...args) {
    return this.sessionClient.installPbwViaNativeInstaller(...args)
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

  reapplySimulatorSettingsToQemu(...args) { return this.simulatorDelivery.reapplySimulatorSettingsToQemu(...args) }
  applyInitialSimulatorSettings(...args) { return this.simulatorDelivery.applyInitialSimulatorSettings(...args) }
  parseSimulatorCapabilities(...args) { return this.simulatorDelivery.parseSimulatorCapabilities(...args) }
  simulatorCapabilities(...args) { return this.simulatorDelivery.simulatorCapabilities(...args) }
  simulatorWeatherEnabled(...args) { return this.simulatorDelivery.simulatorWeatherEnabled(...args) }
  refreshSimulatorCapabilities(...args) { return this.simulatorDelivery.refreshSimulatorCapabilities(...args) }
  companionSimulatorEnabled(...args) { return this.simulatorDelivery.companionSimulatorEnabled(...args) }
  emulatorSessionActive(...args) { return this.simulatorDelivery.emulatorSessionActive(...args) }
  shouldSyncCompanionSimulator(...args) { return this.simulatorDelivery.shouldSyncCompanionSimulator(...args) }
  simulatorSettingsWeatherKey(...args) { return this.simulatorDelivery.simulatorSettingsWeatherKey(...args) }
  syncSimulatorSettingsFromDataset(...args) { return this.simulatorDelivery.syncSimulatorSettingsFromDataset(...args) }
  refreshSimulatorSettingsFromDataset(...args) { return this.simulatorDelivery.refreshSimulatorSettingsFromDataset(...args) }
  applySimulatorSettings(...args) { return this.simulatorDelivery.applySimulatorSettings(...args) }
  simulatorSettingsPayload(...args) { return this.simulatorDelivery.simulatorSettingsPayload(...args) }
  pushSimulatorSettingsToPhoneBridgeNow(...args) { return this.simulatorDelivery.pushSimulatorSettingsToPhoneBridgeNow(...args) }
  scheduleWeatherPush(...args) { return this.simulatorDelivery.scheduleWeatherPush(...args) }
  scheduleWeatherDebugFallback(...args) { return this.simulatorDelivery.scheduleWeatherDebugFallback(...args) }
  scheduleWeatherDebugAckTimeout(...args) { return this.simulatorDelivery.scheduleWeatherDebugAckTimeout(...args) }
  weatherDebugQueueKey(...args) { return this.simulatorDelivery.weatherDebugQueueKey(...args) }
  enqueueWeatherDebugPush(...args) { return this.simulatorDelivery.enqueueWeatherDebugPush(...args) }
  drainWeatherDebugQueue(...args) { return this.simulatorDelivery.drainWeatherDebugQueue(...args) }
  logWeatherTrace(...args) { return this.simulatorDelivery.logWeatherTrace(...args) }
  resetWeatherDebugQueueIfStuck(...args) { return this.simulatorDelivery.resetWeatherDebugQueueIfStuck(...args) }
  weatherConditionWireCode(...args) { return this.simulatorDelivery.weatherConditionWireCode(...args) }
  parseSimulatorTemperatureC(...args) { return this.simulatorDelivery.parseSimulatorTemperatureC(...args) }
  resolveWeatherSimulatorSettings(...args) { return this.simulatorDelivery.resolveWeatherSimulatorSettings(...args) }
  scheduleWeatherSimulatorInject(...args) { return this.simulatorDelivery.scheduleWeatherSimulatorInject(...args) }
  injectWeatherSimulatorSettings(...args) { return this.simulatorDelivery.injectWeatherSimulatorSettings(...args) }
  pushWeatherDebugAppMessage(...args) { return this.simulatorDelivery.pushWeatherDebugAppMessage(...args) }
  sendWeatherSimulatorSettings(...args) { return this.simulatorDelivery.sendWeatherSimulatorSettings(...args) }
  sendSimulatorSettingsToPhoneBridge(...args) { return this.simulatorDelivery.sendSimulatorSettingsToPhoneBridge(...args) }

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

  formatLastQemuSettingsApply() {
    const apply = this.lastQemuSettingsApply
    if (!apply) return "(none)"
    const names = Array.isArray(apply.protocols)
      ? apply.protocols.map(p => p?.name || p).filter(Boolean).join(", ")
      : ""
    return `count=${apply.count ?? 0}, source=${apply.source ?? "?"}` + (names ? `, protocols=${names}` : "")
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
      `Data log entries: ${this.dataLogEntries?.length ?? 0}`,
      `Simulator settings source: ${this.simulatorSettingsSource ?? "(none)"}`,
      `Simulator settings applied at: ${this.simulatorSettingsAppliedAt ? new Date(this.simulatorSettingsAppliedAt).toISOString() : "(none)"}`,
      `Last QEMU settings apply: ${this.formatLastQemuSettingsApply()}`
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

  schedulePingAfterDisplayConnect(...args) {
    return this.sessionClient.schedulePingAfterDisplayConnect(...args)
  }

  stopPingAfterDisplayTimer() {
    if (this.pingAfterDisplayTimer) window.clearTimeout(this.pingAfterDisplayTimer)
    this.pingAfterDisplayTimer = null
  }

  startPing(...args) {
    return this.sessionClient.startPing(...args)
  }

  stopPing() {
    if (this.pingTimer) window.clearInterval(this.pingTimer)
    this.pingTimer = null
  }

  async pingSession(...args) {
    return this.sessionClient.pingSession(...args)
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
