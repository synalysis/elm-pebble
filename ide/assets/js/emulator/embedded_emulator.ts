/** Embedded Pebble emulator browser host (QEMU + Phoenix VNC channel). */

import {postJSON, websocketURL} from "./emulator_http"
import {EmulatorVnc} from "./emulator_vnc"
import {EmulatorSessionClient} from "./emulator_session_client"
import {EmulatorSimulatorDelivery} from "./emulator_simulator_delivery"
import {
  applySimulatorSettingsToQemu,
  BUTTONS,
  encodeAccel,
  encodeBattery,
  encodeCompass,
  QEMU
} from "./qemu_control"
import {disconnectUserSocket, getUserSocket, waitForUserSocketOpen} from "../user_socket"
import type {HookContext} from "../types/liveview_hook"
import type {
  DataLogEntry,
  EmbeddedEmulatorRuntimeState,
  PendingPypkjsInstall,
  StorageEntry
} from "../types/embedded_emulator_state"
import type {EmulatorScreen, EmulatorSessionInfo, SimulatorSettings} from "../types/emulator"
import type {AppendLogOptions, EmulatorVncHost} from "../types/emulator_host"
import type {QuietOptions, SimulatorSettingsOptions, WeatherSimulatorSettings} from "../types/emulator_options"
import type {SimulatorDeliveryHost} from "../types/simulator_host"
import {errMessage} from "../types/errors"
import {classifyWatchFault, type WatchFault} from "./watch_fault"
import type RFB from "@novnc/novnc"
const CONFIG_RETURN_PATH = "/api/emulator/config-return"
const MAX_LOG_LINES = 300
const MAX_LOG_CHARS = 40000
const PUTBYTES_SUMMARY_INTERVAL = 25
const SYSTEM_LOG_SUMMARY_INTERVAL = 50
// Large phone companions (YES + geolocation) can exceed 2 minutes on first cache load.
const PHONE_BRIDGE_INSTALL_TIMEOUT_MS = 300_000
/** Let native watch install and AppMessage traffic settle before reloading phone JS. */
const PHONE_COMPANION_INSTALL_DELAY_MS = 2_000
/** Let native watch install and first scene build settle before AppLog shipping. */
const WATCH_APP_LOG_SHIPPING_DELAY_MS = 8_000
/** Ignore phone-bridge close events briefly after a successful companion cache load. */
const PHONE_BRIDGE_POST_INSTALL_QUIET_MS = 4_000
const PHONE_BRIDGE_RECONNECT_MAX = 4
const PHONE_BRIDGE_RECONNECT_WINDOW_MS = 60_000
/** Minimum gap between successful phone-bridge reconnects (avoids 1011 proxy storms). */
const PHONE_BRIDGE_RECONNECT_COOLDOWN_MS = 8_000
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
  weatherConditionWire: 0x454c4d13,
  companionResync: 0x454c4d14
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

const EMBEDDED_EMULATOR_UI_BUILD = "v24-display-ready"
const PHOENIX_SOCKET_OPEN_TIMEOUT_MS = 10_000
const VNC_CHANNEL_JOIN_TIMEOUT_MS = 10_000
const APP_RUN_STATE_START_DEBOUNCE_MS = 2_000

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

function emulatorStateKey(el: HTMLElement): string {
  return el.dataset.projectSlug || "default"
}

function defaultEmulatorState(key: string): EmbeddedEmulatorRuntimeState {
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

function emulatorStateFor(el: HTMLElement): EmbeddedEmulatorRuntimeState {
  const key = emulatorStateKey(el)
  if (!embeddedEmulatorStates.has(key)) embeddedEmulatorStates.set(key, defaultEmulatorState(key))
  return embeddedEmulatorStates.get(key)!
}

type PersistedStateField = (typeof persistedStateFields)[number]

function definePersistedState(host: EmbeddedEmulatorHost): void {
  persistedStateFields.forEach((field: PersistedStateField) => {
    Object.defineProperty(host, field, {
      get(this: EmbeddedEmulatorHost) {
        return this.state[field as keyof EmbeddedEmulatorRuntimeState]
      },
      set(this: EmbeddedEmulatorHost, value: EmbeddedEmulatorRuntimeState[keyof EmbeddedEmulatorRuntimeState]) {
        ;(this.state as Record<PersistedStateField, unknown>)[field] = value
      }
    })
  })
}

type EmulatorButtonName = keyof typeof BUTTONS


export class EmbeddedEmulatorHost implements SimulatorDeliveryHost, EmulatorVncHost {
  hook: HookContext
  el: HTMLElement
  state: EmbeddedEmulatorRuntimeState
  session!: EmulatorSessionInfo | null
  buttonState!: number
  launching!: boolean
  installing!: boolean
  appInstalled!: boolean
  stopping!: boolean
  pendingPypkjsInstall!: PendingPypkjsInstall | null
  currentStatus!: string | null
  logLines!: string[]
  storageEntries!: Map<string, StorageEntry>
  suppressedPutBytesFrames!: number
  suppressedSystemLogFrames!: number
  sessionEnded!: boolean
  sessionAlive!: boolean
  displayConnected!: boolean
  phoneBridgeReady!: boolean
  phoneBridgeActive!: boolean
  dataLogEntries!: DataLogEntry[]
  rfb!: RFB | null
  rfbCanvas!: HTMLElement | null
  vncConnecting!: boolean
  reconnectingVnc!: boolean
  vncReconnectTimer!: ReturnType<typeof setTimeout> | null
  vncReconnectAttempts!: number
  destroyed = false
  phoneSocket: WebSocket | null = null
  pingTimer: ReturnType<typeof setInterval> | null = null
  pingAfterDisplayTimer: ReturnType<typeof setTimeout> | null = null
  configUrl: string | null = null
  configPopupTimer: ReturnType<typeof setInterval> | null = null
  phoneOpenedAt = 0
  phoneCompanionCacheInstalled = false
  phoneCompanionInstalledAt = 0
  phoneBridgeReconnectInFlight = false
  phoneBridgeReconnectAttempts = 0
  phoneBridgeReconnectWindowStartedAt = 0
  phoneBridgeLastReconnectedAt = 0
  targetChangeStopInFlight = false
  logFlushScheduled = false
  simulatorDelivery: EmulatorSimulatorDelivery
  sessionClient: EmulatorSessionClient
  vnc: EmulatorVnc
  lastQemuSettingsApply: SimulatorDeliveryHost["lastQemuSettingsApply"] = null
  simulatorSettings: SimulatorSettings | null = null
  lastAppliedSimulatorSettingsJson: string | null = null
  simulatorSettingsSource: string | null = null
  simulatorSettingsAppliedAt = 0
  weatherInjectTimers: ReturnType<typeof setTimeout>[] = []
  weatherPushTimer: ReturnType<typeof setTimeout> | null = null
  weatherPushRetryTimers: ReturnType<typeof setTimeout>[] = []
  weatherDebugQueue: SimulatorDeliveryHost["weatherDebugQueue"] = []
  weatherDebugInFlight = false
  weatherDebugInFlightAt = 0
  weatherDebugAckTimer: ReturnType<typeof setTimeout> | null = null
  deferredStorageSnapshotTimer: ReturnType<typeof setTimeout> | null = null
  weatherDebugFallbackTimer: ReturnType<typeof setTimeout> | null = null
  pendingWeatherRetry: WeatherSimulatorSettings | null = null
  lastSentWeatherJson: string | null = null
  vncViewportConfigKey: string | null = null
  vncViewportConfigTimer: ReturnType<typeof setTimeout> | null = null
  vncSocket: WebSocket | null = null
  vncChannel: EmulatorVncHost["vncChannel"] = null
  vncPhoenixSocket: EmulatorVncHost["vncPhoenixSocket"] = null
  vncPendingFrames: ArrayBuffer[] = []
  vncFrameSink: ((data: ArrayBuffer) => void) | null = null
  vncJoinInitial: ArrayBuffer | null = null
  vncLoggedFirstSend = false
  vncWsDiag: EmulatorVncHost["vncWsDiag"] = null
  vncSessionProbe: EmulatorVncHost["vncSessionProbe"] = null
  _simulatorCapabilities?: Set<string>
  boundEmulatorButtons = new WeakSet<Element>()
  boundControlElements = new WeakSet<Element>()
  syncStateToDom: () => void
  handlePageVisible: () => void
  handleConfigKeyDown: (event: KeyboardEvent) => void
  handleRootClick: (event: MouseEvent) => void
  canvas: HTMLElement | null = null
  status: HTMLElement | null = null
  log: HTMLElement | null = null
  configPanel: HTMLElement | null = null
  configDialog: HTMLElement | null = null
  configFrame: HTMLIFrameElement | null = null
  configUrlLabel: HTMLElement | null = null
  launchButton: HTMLButtonElement | null = null
  installButton: HTMLButtonElement | null = null
  preferencesButton: HTMLButtonElement | null = null
  screenshotButton: HTMLButtonElement | null = null
  storageRows: HTMLElement | null = null
  storageResetButton: HTMLButtonElement | null = null
  storageAddButton: HTMLButtonElement | null = null
  storageNewKey: HTMLInputElement | null = null
  storageNewType: HTMLSelectElement | null = null
  storageNewValue: HTMLInputElement | null = null
  dataLogRows: HTMLElement | null = null
  faultBanner: HTMLElement | null = null
  faultHeadline: HTMLElement | null = null
  faultDetail: HTMLElement | null = null
  watchFault: WatchFault | null = null
  watchAppLogShippingEnabled = false
  lastAppRunStateStartKey: string | null = null
  lastAppRunStateStartAt = 0

  constructor(hook: HookContext) {
    this.hook = hook
    this.el = hook.el
    this.state = emulatorStateFor(this.el)
    definePersistedState(this)
    this.phoneSocket = null
    this.pingTimer = null
    this.configUrl = null
    this.configPopupTimer = null
    this.phoneOpenedAt = 0
    this.phoneCompanionCacheInstalled = false
    this.phoneCompanionInstalledAt = 0
    this.phoneBridgeReconnectInFlight = false
    this.phoneBridgeReconnectAttempts = 0
    this.phoneBridgeReconnectWindowStartedAt = 0
    this.phoneBridgeLastReconnectedAt = 0
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
    this.handleConfigKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && this.configPanel && !this.configPanel.classList.contains("hidden")) {
        this.cancelConfig()
      }
    }
    this.handleRootClick = (event: MouseEvent) => {
      if (this.destroyed) return
      const target = event.target
      if (!(target instanceof Element)) return
      if (target.closest("[data-emulator-launch]")) {
        event.preventDefault()
        this.toggleLaunch()
        return
      }
      if (target.closest("[data-emulator-install]")) {
        event.preventDefault()
        void this.install()
        return
      }
      if (target.closest("[data-emulator-preferences]")) {
        event.preventDefault()
        void this.loadCompanionPreferences()
        return
      }
      if (target.closest("[data-emulator-screenshot]")) {
        event.preventDefault()
        void this.captureScreenshot()
        return
      }
      if (target.closest("[data-emulator-copy-feedback]")) {
        event.preventDefault()
        void this.copyFeedbackReport()
        return
      }
      if (target.closest("[data-emulator-storage-reset]")) {
        event.preventDefault()
        void this.resetStorage()
        return
      }
      if (target.closest("[data-emulator-storage-add]")) {
        event.preventDefault()
        void this.saveNewStorageEntry()
        return
      }
      if (target.closest("[data-emulator-config-cancel]")) {
        event.preventDefault()
        this.cancelConfig()
        return
      }
      if (target.closest("[data-emulator-tap]")) {
        event.preventDefault()
        this.sendQemu(QEMU.tap, [0, 1])
        return
      }
      if (target.closest("[data-emulator-compass-send]")) {
        event.preventDefault()
        this.sendCompassSample()
      }
    }
  }

  mount(): void {
    this.canvas = this.el.querySelector("[data-emulator-canvas]")
    this.status = this.el.querySelector("[data-emulator-status]")
    this.faultBanner = this.el.querySelector("[data-emulator-fault-banner]")
    this.faultHeadline = this.el.querySelector("[data-emulator-fault-headline]")
    this.faultDetail = this.el.querySelector("[data-emulator-fault-detail]")
    this.log = this.el.querySelector("[data-emulator-log]")
    this.configPanel = this.el.querySelector("[data-emulator-config-panel]")
    this.configDialog = this.el.querySelector("[data-emulator-config-dialog]")
    this.configFrame = this.el.querySelector<HTMLIFrameElement>("[data-emulator-config-frame]")
    this.configUrlLabel = this.el.querySelector("[data-emulator-config-url]")
    this.launchButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-launch]")
    this.installButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-install]")
    this.preferencesButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-preferences]")
    this.screenshotButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-screenshot]")
    this.storageRows = this.el.querySelector("[data-emulator-storage-rows]")
    this.storageResetButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-storage-reset]")
    this.storageAddButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-storage-add]")
    this.storageNewKey = this.el.querySelector<HTMLInputElement>("[data-emulator-storage-new-key]")
    this.storageNewType = this.el.querySelector<HTMLSelectElement>("[data-emulator-storage-new-type]")
    this.storageNewValue = this.el.querySelector<HTMLInputElement>("[data-emulator-storage-new-value]")
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

  updated(): void {
    const previousCanvas = this.canvas
    this.refreshSimulatorCapabilities()
    this.canvas = this.el.querySelector("[data-emulator-canvas]")
    this.status = this.el.querySelector("[data-emulator-status]")
    this.faultBanner = this.el.querySelector("[data-emulator-fault-banner]")
    this.faultHeadline = this.el.querySelector("[data-emulator-fault-headline]")
    this.faultDetail = this.el.querySelector("[data-emulator-fault-detail]")
    this.log = this.el.querySelector("[data-emulator-log]")
    this.launchButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-launch]")
    this.installButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-install]")
    this.preferencesButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-preferences]")
    this.screenshotButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-screenshot]")
    this.storageRows = this.el.querySelector("[data-emulator-storage-rows]")
    this.storageResetButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-storage-reset]")
    this.storageAddButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-storage-add]")

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
    void this.reconcileSessionWithSelectedTarget()
    if (this.session?.backend_enabled && this.rfb && previousCanvas && previousCanvas !== this.canvas) {
    
      this.reconnectVncAfterDomPatch()
    }
    this.ensureVncAttached()
  }

  async initializePersistedSession(): Promise<void> {
    if (!this.session) {
      this.updateControlButtons()
      return
    }

    await this.validatePersistedSession()
    if (!this.session) {
      this.updateControlButtons()
      return
    }

    if (this.sessionTargetMismatch()) {
      await this.stopSessionForTargetChange()
      this.updateControlButtons()
      return
    }

    this.resumeExistingSession()
    this.ensureVncAttached()
    this.updateControlButtons()
  }

  validatePersistedSession(): ReturnType<InstanceType<typeof EmulatorSessionClient>["validatePersistedSession"]> {
    return this.sessionClient.validatePersistedSession()
  }

  resumeExistingSession(): void {
    if (!this.session) return

    this.sessionEnded = false
    this.applyCanvasSize()
    if (this.session.backend_enabled && !(this.rfb && this.rfbCanvas === this.canvas)) {
      this.connectDisplay().catch(error => {
        if (this.session && !this.stopping && !this.destroyed) {
          this.scheduleVncReconnect(`Embedded emulator display reconnect failed: ${errMessage(error)}`)
        }
      })
    }
    if (this.sessionAlive) this.schedulePingAfterDisplayConnect()
    this.reapplySimulatorSettingsToQemu({source: "session_resume", quiet: true})
  }

  destroy(removeListeners = true): void {
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
    this.weatherInjectTimers.forEach((timerId: ReturnType<typeof setTimeout>) => window.clearTimeout(timerId))
    this.weatherInjectTimers = []
    this.weatherPushRetryTimers.forEach((timerId: ReturnType<typeof setTimeout>) => window.clearTimeout(timerId))
    this.weatherPushRetryTimers = []
    if (this.weatherDebugFallbackTimer != null) {
      window.clearTimeout(this.weatherDebugFallbackTimer)
      this.weatherDebugFallbackTimer = null
    }
    if (this.weatherDebugAckTimer != null) {
      window.clearTimeout(this.weatherDebugAckTimer)
      this.weatherDebugAckTimer = null
    }
    if (this.deferredStorageSnapshotTimer != null) {
      window.clearTimeout(this.deferredStorageSnapshotTimer)
      this.deferredStorageSnapshotTimer = null
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

  notifyStateChanged(): void {
    this.state.listeners.forEach((listener: () => void) => listener())
  }

  toggleLaunch(): void {
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

  async launch(): ReturnType<InstanceType<typeof EmulatorSessionClient>["launch"]> {
    return this.sessionClient.launch()
  }

  async stop(reason?: string): ReturnType<InstanceType<typeof EmulatorSessionClient>["stop"]> {
    return this.sessionClient.stop(reason)
  }

  resolveCanvas(): ReturnType<InstanceType<typeof EmulatorVnc>["resolveCanvas"]> {
    return this.vnc.resolveCanvas()
  }
  waitForDisplayReady(timeoutMs?: number): ReturnType<InstanceType<typeof EmulatorVnc>["waitForDisplayReady"]> {
    return this.vnc.waitForDisplayReady(timeoutMs)
  }
  connectDisplay(): ReturnType<InstanceType<typeof EmulatorVnc>["connectDisplay"]> {
    return this.vnc.connectDisplay()
  }
  closeVncSocket(): void {
    return this.vnc.closeVncSocket()
  }
  closeVncChannel(): void {
    return this.vnc.closeVncChannel()
  }
  disconnectRfb(rfb: RFB | null | undefined, options?: {reconnecting?: boolean}): void {
    return this.vnc.disconnectRfb(rfb, options)
  }
  ensurePhoenixSocket(): ReturnType<InstanceType<typeof EmulatorVnc>["ensurePhoenixSocket"]> {
    return this.vnc.ensurePhoenixSocket()
  }
  decodeChannelBinary(
    payload: Parameters<InstanceType<typeof EmulatorVnc>["decodeChannelBinary"]>[0]
  ): ReturnType<InstanceType<typeof EmulatorVnc>["decodeChannelBinary"]> {
    return this.vnc.decodeChannelBinary(payload)
  }
  base64ToArrayBuffer(encoded: string): ArrayBuffer {
    return this.vnc.base64ToArrayBuffer(encoded)
  }
  vncBytes(data: ArrayBuffer | ArrayBufferView): Uint8Array {
    return this.vnc.vncBytes(data)
  }
  bytesToBase64(bytes: Uint8Array): string {
    return this.vnc.bytesToBase64(bytes)
  }
  pushVncFrame(
    channel: Parameters<InstanceType<typeof EmulatorVnc>["pushVncFrame"]>[0],
    data: ArrayBuffer | ArrayBufferView
  ): void {
    return this.vnc.pushVncFrame(channel, data)
  }
  resetVncFramePipeline(): void {
    return this.vnc.resetVncFramePipeline()
  }
  enqueueVncChannelFrame(payload: unknown): void {
    return this.vnc.enqueueVncChannelFrame(payload)
  }
  bindVncFrameSink(deliver: (data: ArrayBuffer) => void): void {
    return this.vnc.bindVncFrameSink(deliver)
  }
  deliverVncJoinInitial(rfb: RFB): void {
    return this.vnc.deliverVncJoinInitial(rfb)
  }
  joinVncChannel(): ReturnType<InstanceType<typeof EmulatorVnc>["joinVncChannel"]> {
    return this.vnc.joinVncChannel()
  }
  createVncChannelTransport(
    channel: Parameters<InstanceType<typeof EmulatorVnc>["createVncChannelTransport"]>[0]
  ): ReturnType<InstanceType<typeof EmulatorVnc>["createVncChannelTransport"]> {
    return this.vnc.createVncChannelTransport(channel)
  }
  resetVncWsDiag(): void {
    return this.vnc.resetVncWsDiag()
  }
  attachVncWebSocketDiagnostics(ws: WebSocket): void {
    return this.vnc.attachVncWebSocketDiagnostics(ws)
  }
  probeEmulatorSession(pingPath: string): ReturnType<InstanceType<typeof EmulatorVnc>["probeEmulatorSession"]> {
    return this.vnc.probeEmulatorSession(pingPath)
  }
  openVncWebSocket(url: string): ReturnType<InstanceType<typeof EmulatorVnc>["openVncWebSocket"]> {
    return this.vnc.openVncWebSocket(url)
  }
  connectVnc(): ReturnType<InstanceType<typeof EmulatorVnc>["connectVnc"]> {
    return this.vnc.connectVnc()
  }
  reconnectVncAfterDomPatch(): void {
    return this.vnc.reconnectVncAfterDomPatch()
  }
  ensureVncAttached(): void {
    return this.vnc.ensureVncAttached()
  }
  scheduleVncReconnect(message: string): void {
    return this.vnc.scheduleVncReconnect(message)
  }
  stopVncReconnect(): void {
    return this.vnc.stopVncReconnect()
  }
  readVncBackingSize(): ReturnType<InstanceType<typeof EmulatorVnc>["readVncBackingSize"]> {
    return this.vnc.readVncBackingSize()
  }
  readVncFramebufferSize(rfb: RFB): ReturnType<InstanceType<typeof EmulatorVnc>["readVncFramebufferSize"]> {
    return this.vnc.readVncFramebufferSize(rfb)
  }
  scheduleVncViewportConfig(rfb: RFB, reason: string, delayMs?: number): void {
    return this.vnc.scheduleVncViewportConfig(rfb, reason, delayMs)
  }
  configureVncDisplay(rfb: RFB, reason?: string): void {
    return this.vnc.configureVncDisplay(rfb, reason)
  }
  scheduleVncCanvasSample(label: string, delayMs?: number): void {
    return this.vnc.scheduleVncCanvasSample(label, delayMs)
  }
  logVncCanvasSample(label: string): void {
    return this.vnc.logVncCanvasSample(label)
  }
  connectPhone(): void {
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
      if (this.appInstalled) void this.ensureWatchAppLogShipping({quiet: true})
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
      if (
        this.session &&
        !this.stopping &&
        !this.installing &&
        !this.phoneBridgeReconnectInFlight &&
        this.phoneOpenedAt > 0
      ) {
        void this.reconnectPhoneBridgeAfterDisconnect()
      }
    })
  }

  async install(): Promise<void> {
    if (this.installing || !this.installReady()) return
    const session = this.session
    if (!session) return
    if (this.sessionTargetMismatch()) {
      this.setStatus(
        `Cannot install: emulator is running ${session.platform} but ${this.selectedEmulatorTarget()} is selected. Launch again.`
      )
      return
    }
    const installSessionId = session.id
    this.installing = true
    this.updateControlButtons()

    try {
      await this.installPbwViaNativeInstaller(installSessionId)
      if (this.session?.id !== installSessionId) return
      if (this.session?.backend_enabled) {
        try {
          await this.waitForSessionAlive(30_000)
          if (this.session?.has_phone_companion) {
            await this.ensurePhoneBridge(45_000)
            if (this.session?.id !== installSessionId) return
          }
        } catch (error) {
          if (this.session?.id === installSessionId) {
            this.appendLog(`phone bridge connect failed after install: ${errMessage(error)}`)
          }
        }
        if (this.session?.id !== installSessionId) return
        window.setTimeout(() => {
          if (this.session?.id !== installSessionId) return
          void this.ensureWatchAppLogShipping({quiet: true})
        }, WATCH_APP_LOG_SHIPPING_DELAY_MS)
        if (this.emulatorDebugEnabled()) this.scheduleDeferredStorageSnapshot()
      }
      if (this.session?.has_phone_companion && this.session?.backend_enabled && this.session?.artifact_path) {
        try {
          await this.ensurePhoneBridge()
          if (this.session?.id !== installSessionId) return
          await new Promise<void>(resolve =>
            window.setTimeout(resolve, PHONE_COMPANION_INSTALL_DELAY_MS)
          )
          if (this.session?.id !== installSessionId) return
          await this.installPbwViaPhoneBridge()
        } catch (error) {
          if (this.session?.id === installSessionId) {
            const message = errMessage(error)
            if (message.includes("Timed out waiting for phone bridge PBW install")) {
              this.appendLog(
                `${message} (companion JS may still be running; check pebble-js-app logs above)`
              )
            } else {
              this.appendLog(`phone bridge companion cache refresh failed: ${message}`)
            }
          }
        }
      }
    } catch (error) {
      if (this.session?.id === installSessionId && !this.stopping) {
        this.setStatus(`PBW install failed: ${errMessage(error)}`)
      }
    } finally {
      if (this.session?.id === installSessionId) {
        this.installing = false
      }
      this.updateControlButtons()
    }
  }

  installPbwViaNativeInstaller(
    installSessionId?: string
  ): ReturnType<InstanceType<typeof EmulatorSessionClient>["installPbwViaNativeInstaller"]> {
    return this.sessionClient.installPbwViaNativeInstaller(installSessionId)
  }

  async reconnectPhoneBridgeAfterDisconnect(): Promise<void> {
    if (
      !this.session?.backend_enabled ||
      this.destroyed ||
      this.stopping ||
      this.phoneBridgeReconnectInFlight
    ) {
      return
    }

    const now = Date.now()
    if (
      this.phoneBridgeLastReconnectedAt > 0 &&
      now - this.phoneBridgeLastReconnectedAt < PHONE_BRIDGE_RECONNECT_COOLDOWN_MS
    ) {
      return
    }
    if (now - this.phoneCompanionInstalledAt < PHONE_BRIDGE_POST_INSTALL_QUIET_MS) {
      await new Promise<void>(resolve =>
        window.setTimeout(resolve, PHONE_BRIDGE_POST_INSTALL_QUIET_MS - (now - this.phoneCompanionInstalledAt))
      )
      if (this.destroyed || !this.session || this.phoneSocket?.readyState === WebSocket.OPEN) return
    }

    if (now - this.phoneBridgeReconnectWindowStartedAt > PHONE_BRIDGE_RECONNECT_WINDOW_MS) {
      this.phoneBridgeReconnectAttempts = 0
      this.phoneBridgeReconnectWindowStartedAt = now
    }
    this.phoneBridgeReconnectAttempts += 1
    if (this.phoneBridgeReconnectAttempts > PHONE_BRIDGE_RECONNECT_MAX) {
      this.endSession("Embedded emulator phone bridge disconnected too many times")
      return
    }

    this.phoneBridgeReconnectInFlight = true
    this.appendLog("phone bridge disconnected; attempting reconnect...")
    try {
      await new Promise<void>(resolve => window.setTimeout(resolve, 2_000))
      if (this.destroyed || !this.session) return
      await this.waitForPhoneBridgeReady(30_000)
      if (this.destroyed || !this.session) return
      await this.ensurePhoneBridge(45_000)
      if (this.destroyed || !this.session) return
      this.phoneBridgeLastReconnectedAt = Date.now()
      this.appendLog("phone bridge reconnected")
      if (this.appInstalled) await this.ensureWatchAppLogShipping({quiet: true})
      if (this.phoneCompanionCacheInstalled) {
        this.sendSimulatorSettingsToPhoneBridge({quiet: true})
      } else if (this.session.has_phone_companion && this.session.artifact_path) {
        await this.installPbwViaPhoneBridge()
      }
    } catch (error) {
      if (!this.destroyed && this.session && !this.stopping) {
        this.endSession(`Embedded emulator phone bridge disconnected (${errMessage(error)})`)
      }
    } finally {
      this.phoneBridgeReconnectInFlight = false
    }
  }

  async waitForSessionAlive(timeoutMs = 20_000): Promise<void> {
    if (!this.session?.ping_path) return

    const startedAt = Date.now()
    while (Date.now() - startedAt < timeoutMs) {
      if (this.destroyed || !this.session?.ping_path) return
      try {
        const info = await postJSON<{alive?: boolean}>(this.session.ping_path)
        if (info?.alive === true) return
      } catch (_error) {
        // session may still be restarting pypkjs
      }
      await new Promise<void>(resolve => window.setTimeout(resolve, 400))
    }

    throw new Error("Timed out waiting for emulator session to become alive")
  }

  async waitForPhoneBridgeReady(timeoutMs = 30_000): Promise<void> {
    if (!this.session?.ping_path) return

    const needsPhone = this.session.has_phone_companion === true
    const startedAt = Date.now()
    while (Date.now() - startedAt < timeoutMs) {
      if (this.destroyed || !this.session?.ping_path) return
      try {
        const info = await postJSON<{alive?: boolean; phone_bridge_ready?: boolean}>(
          this.session.ping_path
        )
        if (info?.alive === true && (!needsPhone || info.phone_bridge_ready === true)) return
      } catch (_error) {
        // pypkjs may still be restarting after exit 133
      }
      await new Promise<void>(resolve => window.setTimeout(resolve, 500))
    }

    throw new Error("Timed out waiting for phone bridge (pypkjs) to become ready")
  }

  async ensurePhoneBridge(timeoutMs = 35_000): Promise<boolean> {
    if (!this.session?.backend_enabled) return false
    if (this.phoneSocket?.readyState !== WebSocket.OPEN) {
      this.connectPhone()
      await this.waitForPhoneBridge(timeoutMs)
    }
    return true
  }

  waitForPhoneBridge(timeoutMs = 35_000): Promise<void> {
    if (this.phoneSocket?.readyState === WebSocket.OPEN) return Promise.resolve()

    return new Promise<void>((resolve, reject) => {
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

  async loadCompanionPreferences(): Promise<void> {
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

  async handlePhoneMessage(event: MessageEvent<ArrayBuffer | Blob | string>): Promise<void> {
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
      case 0x02: {
        const text = new TextDecoder().decode(data.slice(1))
        if (
          !this.emulatorDebugEnabled() &&
          /Elm companion sendAppMessage payload|platform bridge -> Elm companion/i.test(text)
        ) {
          break
        }
        this.appendLog(this.compactPhoneLog(text))
        break
      }
      case 0x05:
        if (this.pendingPypkjsInstall) {
          this.finishPypkjsInstall(data[data.length - 1] === 0)
          this.setStatus(data[data.length - 1] === 0 ? "Phone companion refreshed" : "Phone companion refresh failed")
        }
        break
      case 0x08:
        this.appendLog(data[1] === 0xff ? "phone bridge connected to watch" : "phone bridge disconnected")
        if (data[1] === 0xff && this.appInstalled) void this.ensureWatchAppLogShipping({quiet: true})
        break
      case 0x09:
        this.appendLog(data[1] === 0 ? "phone bridge authenticated" : "phone bridge authentication failed")
        if (data[1] === 0 && this.appInstalled) void this.ensureWatchAppLogShipping({quiet: true})
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
              this.weatherPushRetryTimers = this.weatherPushRetryTimers.filter(
                (id: ReturnType<typeof setTimeout>) => id !== timerId
              )
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
          if (this.useSimulatorWeather()) {
            const weather = this.resolveWeatherSimulatorSettings()
            this.appendLog(
              `weather trace [browser_ack]: ${this.parseSimulatorTemperatureC(weather?.temperatureC) ?? "?"}°C ${weather?.condition || "clear"}`
            )
          }
        } else {
          this.appendLog("simulator settings sync failed")
          if (this.useSimulatorWeather()) {
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

  logPhoneBridgeFrame(data: Uint8Array): void {
    const opcode = data[0]

    if (opcode === 0x02) {
      const text = new TextDecoder().decode(data.slice(1))
      if (/watch -> Elm companion|Elm companion|AppMessage|not responding|error|failed/i.test(text)) {
        this.appendLog(this.compactPhoneLog(text))
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
        if (endpoint === 0x0034 && opcode === 0x00 && this.acceptAppRunStateStart(payload)) {
          this.handleAppRunStateStart()
        }
        if (this.emulatorDebugEnabled() && endpoint === 0x0030 && opcode === 0x01) {
          this.scheduleVncCanvasSample("after_phone_appmessage_250ms", 250)
          this.scheduleVncCanvasSample("after_phone_appmessage_1500ms", 1500)
        }
      
        if (endpoint === ENDPOINT_DATA_LOGGING) {
          this.recordDataLogEntry(this.describeDataLoggingPayload(payload))
        }
      }
    }
  }

  async messageBytes(data: ArrayBuffer | Blob | string): Promise<ArrayBuffer> {
    if (data instanceof ArrayBuffer) return data
    if (data instanceof Blob) return data.arrayBuffer()
    if (typeof data === "string") return new TextEncoder().encode(data).buffer
    return new ArrayBuffer(0)
  }

  acceptAppRunStateStart(payload: Uint8Array): boolean {
    if (payload.length < 17 || payload[0] !== 0x01) return false
    const appUuid = this.session?.app_uuid
    if (!appUuid) return false
    const frameUuid = this.uuidString(payload.slice(1, 17))
    if (frameUuid !== appUuid.toLowerCase()) return false

    const now = Date.now()
    if (
      this.lastAppRunStateStartKey === frameUuid &&
      now - this.lastAppRunStateStartAt < APP_RUN_STATE_START_DEBOUNCE_MS
    ) {
      return false
    }

    this.lastAppRunStateStartKey = frameUuid
    this.lastAppRunStateStartAt = now
    return true
  }

  handleAppRunStateStart(): void {
    if (this.rfb) this.scheduleVncViewportConfig(this.rfb, "app_start", 500)
    if (this.emulatorDebugEnabled()) {
      this.scheduleVncCanvasSample("after_app_start_250ms", 250)
      this.scheduleVncCanvasSample("after_app_start_1500ms", 1500)
    }
    this.scheduleWeatherSimulatorInject("after_app_start")
    this.scheduleCompanionWatchReadySignal("after_app_start")
  }

  uuidString(bytes: Uint8Array): string {
    if (bytes.length !== 16) return ""
    const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, "0"))
    return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`
  }

  pressButton(name: EmulatorButtonName, down: boolean): void {
    if (!(name in BUTTONS)) return
    const bit = 1 << BUTTONS[name]
    this.buttonState = down ? (this.buttonState | bit) : (this.buttonState & ~bit)
    this.sendQemu(QEMU.button, [this.buttonState])
  }

  bindControl(element: Element | null, eventName: string, handler: EventListener): void {
    if (!element || this.boundControlElements.has(element)) return
    this.boundControlElements.add(element)
    element.addEventListener(eventName, handler)
  }

  bindControlButtons(): void {
    this.launchButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-launch]")
    this.installButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-install]")
    this.preferencesButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-preferences]")
    this.screenshotButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-screenshot]")
    this.storageResetButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-storage-reset]")
    this.storageAddButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-storage-add]")
    this.configPanel = this.el.querySelector("[data-emulator-config-panel]")
    this.configFrame = this.el.querySelector<HTMLIFrameElement>("[data-emulator-config-frame]")

    if (this.configPanel && !this.boundControlElements.has(this.configPanel)) {
      this.boundControlElements.add(this.configPanel)
      this.configPanel.addEventListener("click", (event: MouseEvent) => {
        if (event.target === this.configPanel) this.cancelConfig()
      })
    }

    if (this.configFrame && !this.boundControlElements.has(this.configFrame)) {
      this.boundControlElements.add(this.configFrame)
      this.configFrame.addEventListener("load", () => this.maybeHandleConfigReturn(this.configFrame?.contentWindow ?? null))
    }
  }

  bindEmulatorButtons(): void {
    this.el.querySelectorAll<HTMLElement>("[data-emulator-button]").forEach(button => {
      if (this.boundEmulatorButtons.has(button)) return
      this.boundEmulatorButtons.add(button)

      const name = button.dataset.emulatorButton as EmulatorButtonName | undefined
      if (!name || !(name in BUTTONS)) return
      button.addEventListener("pointerdown", (event: PointerEvent) => {
        event.preventDefault()
        button.setPointerCapture?.(event.pointerId)
        this.pressButton(name, true)
      })

      const release = (event: PointerEvent) => {
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

  releaseAllButtons(): void {
    if (this.buttonState === 0) return
    this.buttonState = 0
    this.sendQemu(QEMU.button, [0])
  }

  setBattery(percent: number, charging: boolean): void {
    this.sendQemu(QEMU.battery, encodeBattery(percent, charging))
  }

  sendAccelSample(x: number, y: number, z: number): void {
    this.sendQemu(QEMU.accel, encodeAccel(x, y, z))
  }

  sendCompassSample(settings: SimulatorSettings = this.simulatorSettings || {}): void {
    this.sendQemu(QEMU.compass, encodeCompass(settings))
  }

  reapplySimulatorSettingsToQemu(options?: SimulatorSettingsOptions): void {
    void this.simulatorDelivery.reapplySimulatorSettingsToQemu(options)
  }
  applyInitialSimulatorSettings(): void {
    return this.simulatorDelivery.applyInitialSimulatorSettings()
  }
  parseSimulatorCapabilities(): Set<string> {
    return this.simulatorDelivery.parseSimulatorCapabilities()
  }
  simulatorCapabilities(): Set<string> {
    return this.simulatorDelivery.simulatorCapabilities()
  }
  simulatorWeatherEnabled(): boolean {
    return this.simulatorDelivery.simulatorWeatherEnabled()
  }

  useSimulatorWeather(settings?: SimulatorSettings | null): boolean {
    return this.simulatorDelivery.useSimulatorWeather(settings)
  }
  refreshSimulatorCapabilities(): void {
    return this.simulatorDelivery.refreshSimulatorCapabilities()
  }
  companionSimulatorEnabled(): boolean {
    return this.simulatorDelivery.companionSimulatorEnabled()
  }
  emulatorSessionActive(): boolean {
    return this.simulatorDelivery.emulatorSessionActive()
  }
  shouldSyncCompanionSimulator(options?: SimulatorSettingsOptions): boolean {
    return this.simulatorDelivery.shouldSyncCompanionSimulator(options)
  }
  simulatorSettingsWeatherKey(settings?: SimulatorSettings | null): string {
    return this.simulatorDelivery.simulatorSettingsWeatherKey(settings)
  }
  syncSimulatorSettingsFromDataset(): void {
    return this.simulatorDelivery.syncSimulatorSettingsFromDataset()
  }
  refreshSimulatorSettingsFromDataset(): void {
    return this.simulatorDelivery.refreshSimulatorSettingsFromDataset()
  }
  applySimulatorSettings(
    settings: SimulatorSettings,
    options?: SimulatorSettingsOptions
  ): ReturnType<InstanceType<typeof EmulatorSimulatorDelivery>["applySimulatorSettings"]> {
    return this.simulatorDelivery.applySimulatorSettings(settings, options)
  }
  simulatorSettingsPayload(
    settings?: SimulatorSettings | null
  ): ReturnType<InstanceType<typeof EmulatorSimulatorDelivery>["simulatorSettingsPayload"]> {
    return this.simulatorDelivery.simulatorSettingsPayload(settings)
  }
  pushSimulatorSettingsToPhoneBridgeNow(options?: QuietOptions): boolean {
    return this.simulatorDelivery.pushSimulatorSettingsToPhoneBridgeNow(options)
  }
  scheduleWeatherPush(options?: SimulatorSettingsOptions): void {
    return this.simulatorDelivery.scheduleWeatherPush(options)
  }
  scheduleWeatherDebugFallback(weather: WeatherSimulatorSettings, options?: QuietOptions): void {
    return this.simulatorDelivery.scheduleWeatherDebugFallback(weather, options)
  }
  scheduleWeatherDebugAckTimeout(): void {
    return this.simulatorDelivery.scheduleWeatherDebugAckTimeout()
  }
  weatherDebugQueueKey(weather: WeatherSimulatorSettings | null | undefined): string {
    return this.simulatorDelivery.weatherDebugQueueKey(weather)
  }
  enqueueWeatherDebugPush(
    weather: WeatherSimulatorSettings,
    options?: QuietOptions & {force?: boolean}
  ): boolean {
    return this.simulatorDelivery.enqueueWeatherDebugPush(weather, options)
  }
  drainWeatherDebugQueue(): boolean {
    return this.simulatorDelivery.drainWeatherDebugQueue()
  }
  logWeatherTrace(bytes: ArrayBuffer): void {
    return this.simulatorDelivery.logWeatherTrace(bytes)
  }
  resetWeatherDebugQueueIfStuck(reason: string): boolean {
    return this.simulatorDelivery.resetWeatherDebugQueueIfStuck(reason)
  }
  weatherConditionWireCode(condition: string | undefined): number {
    return this.simulatorDelivery.weatherConditionWireCode(condition)
  }
  parseSimulatorTemperatureC(value: unknown): number | null {
    return this.simulatorDelivery.parseSimulatorTemperatureC(value)
  }
  resolveWeatherSimulatorSettings(
    settings?: SimulatorSettings | null
  ): ReturnType<InstanceType<typeof EmulatorSimulatorDelivery>["resolveWeatherSimulatorSettings"]> {
    return this.simulatorDelivery.resolveWeatherSimulatorSettings(settings)
  }
  scheduleWeatherSimulatorInject(reason: string): void {
    return this.simulatorDelivery.scheduleWeatherSimulatorInject(reason)
  }

  scheduleCompanionWatchReadySignal(reason: string): void {
    return this.simulatorDelivery.scheduleCompanionWatchReadySignal(reason)
  }
  injectWeatherSimulatorSettings(reason: string): void {
    return this.simulatorDelivery.injectWeatherSimulatorSettings(reason)
  }
  pushWeatherDebugAppMessage(
    weather: WeatherSimulatorSettings,
    options?: QuietOptions
  ): boolean {
    return this.simulatorDelivery.pushWeatherDebugAppMessage(weather, options)
  }
  sendWeatherSimulatorSettings(
    weather: WeatherSimulatorSettings,
    options?: QuietOptions
  ): boolean {
    return this.simulatorDelivery.sendWeatherSimulatorSettings(weather, options)
  }
  sendSimulatorSettingsToPhoneBridge(options?: QuietOptions): boolean {
    return this.simulatorDelivery.sendSimulatorSettingsToPhoneBridge(options)
  }

  sendQemu(protocol: number, payload: number[]): void {
    if (!this.session?.id) return
    postJSON(`/api/emulator/${encodeURIComponent(this.session.id)}/control`, {protocol, payload}).catch(error =>
      this.appendLog(`embedded control failed: ${errMessage(error)}`)
    )
  }

  sendPebbleFrame(endpoint: number, payload: Uint8Array): boolean {
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

  async ensureWatchAppLogShipping(options: {quiet?: boolean} = {}): Promise<void> {
    if (this.watchAppLogShippingEnabled) return

    if (this.session?.request_app_logs_path) {
      try {
        await postJSON(this.session.request_app_logs_path)
        if (!options.quiet) {
          this.appendLog("requested watch AppLog shipping via emulator session")
        }
      } catch (error) {
        if (!options.quiet) {
          this.appendLog(`watch AppLog enable via session failed: ${errMessage(error)}`)
        }
      }
    }

    const sent = this.sendPebbleFrame(ENDPOINT_APP_LOG, new Uint8Array([1]))
    if (sent) {
      this.watchAppLogShippingEnabled = true
      if (!options.quiet) {
        this.appendLog("requested watch AppLog shipping via phone bridge")
      }
    } else if (!options.quiet && !this.session?.request_app_logs_path) {
      this.appendLog("skipped watch AppLog shipping: phone bridge is not connected")
    }
  }

  scheduleDeferredStorageSnapshot(delayMs = 3000): void {
    if (this.deferredStorageSnapshotTimer != null) return
    this.deferredStorageSnapshotTimer = window.setTimeout(() => {
      this.deferredStorageSnapshotTimer = null
      this.requestStorageSnapshot()
    }, delayMs)
  }

  requestStorageSnapshot(): void {
    if (!this.sendDebugAppMessage([{key: DEBUG_STORAGE.op, type: "uint", value: DEBUG_STORAGE.opSnapshot}], {quiet: true})) {
      return
    }
    this.appendLog("requested watch storage snapshot")
  }

  phoneBridgeSimulatorSettings(): ReturnType<InstanceType<typeof EmulatorSimulatorDelivery>["simulatorSettingsPayload"]> {
    return this.simulatorSettingsPayload()
  }

  async installPbwViaPhoneBridge(): Promise<void> {
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
    this.phoneCompanionCacheInstalled = true
    this.phoneCompanionInstalledAt = Date.now()
    this.appendLog("phone bridge companion cache refresh complete")
    this.sendSimulatorSettingsToPhoneBridge()
  }

  waitForPypkjsInstall(): Promise<void> {
    if (this.pendingPypkjsInstall) return this.pendingPypkjsInstall.promise

    let pending!: PendingPypkjsInstall
    const promise = new Promise<void>((resolve, reject) => {
      const timeoutId = window.setTimeout(() => {
        this.pendingPypkjsInstall = null
        reject(new Error("Timed out waiting for phone bridge PBW install"))
      }, PHONE_BRIDGE_INSTALL_TIMEOUT_MS)
      pending = {resolve, reject, timeoutId, promise: null!}
      this.pendingPypkjsInstall = pending
    })

    pending.promise = promise
    return promise
  }

  finishPypkjsInstall(success: boolean): void {
    if (!this.pendingPypkjsInstall) return
    const pending = this.pendingPypkjsInstall
    this.pendingPypkjsInstall = null
    window.clearTimeout(pending.timeoutId)

    if (success) {
      pending.resolve()
      if (this.companionSimulatorEnabled() && this.appInstalled) {
        this.scheduleCompanionWatchReadySignal("after_companion_install")
      }
    } else {
      pending.reject(new Error("Phone bridge PBW install failed"))
    }
  }

  appendPebbleFrameLog(direction: string, frame: Uint8Array): void {
    const endpoint = this.pebbleFrameEndpoint(frame)

    if (endpoint === 0xbeef) {
      this.compactPutBytesFrame()
      return
    }

    if (endpoint === ENDPOINT_SYSTEM_LOG) {
      this.compactSystemLogFrame()
      return
    }

    if (endpoint != null) {
      if (endpoint === 0x0030 || endpoint === 0x0034 || endpoint === ENDPOINT_DATA_LOGGING) {
        return
      }
      if (!this.emulatorDebugEnabled() && endpoint === ENDPOINT_APP_LOG) {
        const payload = frame.slice(4)
        const level = payload[20] ?? 0
        if (level !== 1 && level !== 2 && level !== 50) return
      }
    }

    this.flushPutBytesSummary()
    this.flushSystemLogSummary()
    const message = this.describePebbleFrame(direction, frame)
    if (message) {
      this.appendLog(this.formatWatchFaultLogLine(message))
      if (message.includes("draw rendered") && this.rfb) {
        this.scheduleVncViewportConfig(this.rfb, "draw_rendered", 50)
      }
    }
  }

  pebbleFrameEndpoint(frame: Uint8Array): number | null {
    if (frame.length < 4) return null
    return new DataView(frame.buffer, frame.byteOffset, frame.byteLength).getUint16(2, false)
  }

  compactPutBytesFrame(): void {
    this.suppressedPutBytesFrames += 1
    if (this.suppressedPutBytesFrames >= PUTBYTES_SUMMARY_INTERVAL) this.flushPutBytesSummary()
  }

  flushPutBytesSummary(): void {
    if (this.suppressedPutBytesFrames === 0) return
    const count = this.suppressedPutBytesFrames
    this.suppressedPutBytesFrames = 0
    this.appendLog(`suppressed ${count} PutBytes transfer frame${count === 1 ? "" : "s"}`, {flushTransfers: false})
  }

  compactSystemLogFrame(): void {
    this.suppressedSystemLogFrames = (this.suppressedSystemLogFrames || 0) + 1
    if (this.suppressedSystemLogFrames >= SYSTEM_LOG_SUMMARY_INTERVAL) this.flushSystemLogSummary()
  }

  flushSystemLogSummary(): void {
    if (!this.suppressedSystemLogFrames) return
    const count = this.suppressedSystemLogFrames
    this.suppressedSystemLogFrames = 0
    this.appendLog(`suppressed ${count} Pebble system log frame${count === 1 ? "" : "s"}`, {flushSystemLogs: false})
  }

  describePebbleFrame(direction: string, frame: Uint8Array): string | null {
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

  describeAppLogFrame(direction: string, payload: Uint8Array): string {
    if (payload.length >= 40) {
      const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength)
      const level = this.appLogLevelName(payload[20] ?? 0)
      const messageLength = payload[21] ?? 0
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

  describeDataLoggingPayload(payload: Uint8Array): DataLogEntry {
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

  uuidFromBytes(bytes: Uint8Array): string {
    if (bytes.length !== 16) return this.hexPreview(bytes)
    const hex = [...bytes].map(byte => byte.toString(16).padStart(2, "0"))
    return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`
  }

  appLogLevelName(level: number): string {
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

  printableStrings(bytes: Uint8Array): string[] {
    const strings: string[] = []
    let current: number[] = []

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

  cString(bytes: Uint8Array): string {
    const end = bytes.indexOf(0)
    const slice = end >= 0 ? bytes.slice(0, end) : bytes
    return new TextDecoder().decode(slice).trim()
  }

  endpointName(endpoint: number): string {
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

  async waitForPhoneBridgeSettle(): Promise<void> {
    const minimumSettleMs = 5000
    const remaining = minimumSettleMs - (Date.now() - this.phoneOpenedAt)
    if (remaining <= 0) return

    this.setStatus("Waiting for phone bridge to settle before install...")
    await new Promise<void>(resolve => window.setTimeout(resolve, remaining))
  }

  handleConfigFrame(data: Uint8Array): void {
    if (data[1] !== 0x01 || data.length < 6) {
      this.appendLog(`configuration bridge frame ignored: opcode=${data[1] ?? "missing"} bytes=${data.length}`)
      return
    }
    const length = new DataView(data.buffer, data.byteOffset + 2, 4).getUint32(0, false)
    const url = new TextDecoder().decode(data.slice(6, 6 + length))
    this.appendLog(`companion requested configuration URL (${length} bytes)`)
    this.showConfigPage(url)
  }

  showConfigPage(url: string): void {
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

  configUrlSummary(url: string): string {
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

  emulatorDebugEnabled(): boolean {
    return this.el?.dataset.emulatorStorageSnapshot === "true"
  }

  compactPhoneLog(message: string): string {
    if (!message) return message
    const configPrefix = "opening companion configuration "
    const configIndex = message.indexOf(configPrefix)
    if (configIndex >= 0) {
      return `${message.slice(0, configIndex)}${configPrefix}${this.configUrlSummary(message.slice(configIndex + configPrefix.length))}`
    }
    return message
  }

  formatBytes(bytes: number): string {
    if (!Number.isFinite(bytes) || bytes < 1024) return `${bytes || 0} bytes`
    const kib = bytes / 1024
    if (kib < 1024) return `${kib.toFixed(kib >= 10 ? 0 : 1)} KiB`
    const mib = kib / 1024
    return `${mib.toFixed(mib >= 10 ? 0 : 1)} MiB`
  }

  withConfigReturnUrl(url: string): string {
    const normalizedUrl = url.startsWith("data:") ? url.replaceAll("#", "%23") : url
    const target = new URL(normalizedUrl, window.location.href)
    target.searchParams.set("return_to", `${window.location.origin}${CONFIG_RETURN_PATH}?`)
    return target.toString()
  }

  maybeHandleConfigReturn(contentWindow: Window | null): void {
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

  completeConfig(query: string): void {
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

  cancelConfig(): void {
    this.phoneSocket?.send(new Uint8Array([0x0a, 0x03]))
    this.hideConfigPage()
    this.setStatus("Cancelled companion configuration")
  }

  hideConfigPage(): void {
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

  stopConfigPopupPolling(): void {
    if (this.configPopupTimer) window.clearInterval(this.configPopupTimer)
    this.configPopupTimer = null
  }

  storageKeyFromInput(input: HTMLInputElement | null): number | null {
    const key = parseInt(input?.value || "", 10)
    return Number.isInteger(key) && key >= 0 ? key : null
  }

  saveNewStorageEntry(): void {
    const key = this.storageKeyFromInput(this.storageNewKey)
    if (key === null) {
      this.setStatus("Storage key must be a non-negative integer.")
      return
    }
    const type = this.storageNewType?.value === "int" ? "int" : "string"
    const value = this.storageNewValue?.value || ""
    this.saveStorageEntry(key, type, value)
  }

  saveStorageEntry(key: number, type: "string" | "int", value: string): void {
    if (!this.sendDebugStorageWrite(key, type, value)) return
    this.upsertStorageEntry({key, type, value: type === "int" ? String(parseInt(value || "0", 10) || 0) : value})
    this.setStatus(`Saved storage key ${key}`)
  }

  deleteStorageEntry(key: number): void {
    if (!this.sendDebugStorageDelete(key)) return
    this.storageEntries.delete(String(key))
    this.renderStorage()
    this.setStatus(`Deleted storage key ${key}`)
  }

  resetStorage(): void {
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

  sendDebugStorageWrite(key: number, type: "string" | "int", value: string): boolean {
    const entries: Array<{key: number; type: string; value: number | string}> = [
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

  sendDebugStorageDelete(key: number, options: QuietOptions = {}): boolean {
    return this.sendDebugAppMessage(
      [
        {key: DEBUG_STORAGE.op, type: "uint", value: DEBUG_STORAGE.opDelete},
        {key: DEBUG_STORAGE.key, type: "uint", value: key}
      ],
      options
    )
  }

  sendDebugAppMessage(
    entries: Array<{key: number; type: string; value: number | string}>,
    options: QuietOptions = {}
  ): boolean {
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

  upsertStorageEntry(entry: {key: number; type?: "string" | "int"; value?: string}): void {
    this.storageEntries.set(String(entry.key), {
      key: entry.key,
      type: entry.type || "string",
      value: entry.value ?? "",
      updatedAt: Date.now()
    })
    this.renderStorage()
  }

  storageLogBody(message: string): string {
    const appLog = message.match(/AppLog(?:\s+\S+)*\s+[^:]+:\s*(.+)$/)
    return appLog?.[1] ?? message
  }

  observeStorageLog(message: string): void {
    const body = this.storageLogBody(message)
    const match = body.match(/(?:cmd|debug) storage_(read|write)(?:_string)? key=(\d+)(?: value=(.*?)(?:\s+status=|\s+rc=|$))?/)
    if (match?.[2]) {
      const key = parseInt(match[2], 10)
      const stringLike = body.includes("storage_read_string") || body.includes("storage_write_string")
      const value = typeof match[3] === "string" ? match[3] : ""
      this.upsertStorageEntry({key, type: stringLike ? "string" : "int", value})
      return
    }

    const deleted = body.match(/(?:cmd|debug) storage_delete key=(\d+)/)
    if (deleted?.[1]) {
      this.storageEntries.delete(deleted[1])
      this.renderStorage()
    }
  }

  renderStorage(): void {
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

  recordDataLogEntry(entry: DataLogEntry): void {
    if (!entry || entry.payloadPrefix) return
    this.dataLogEntries = [{...entry, recordedAt: Date.now()}, ...this.dataLogEntries].slice(0, 50)
    this.renderDataLog()
  }

  renderDataLog(): void {
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

  dataLogRow(entry: DataLogEntry): HTMLTableRowElement {
    const row = document.createElement("tr")
    row.className = "border-b border-zinc-100 last:border-0"
    row.innerHTML = `
      <td class="px-2 py-1 font-mono text-zinc-800"></td>
      <td class="px-2 py-1 text-zinc-700"></td>
      <td class="px-2 py-1 text-zinc-700"></td>
    `
    const tagCell = row.children.item(0)
    const typeCell = row.children.item(1)
    const sizeCell = row.children.item(2)
    if (tagCell) tagCell.textContent = entry.tagHex || "—"
    if (typeCell) typeCell.textContent = String(entry.itemType ?? "—")
    if (sizeCell) sizeCell.textContent = String(entry.itemSize ?? "—")
    return row
  }

  storageRow(entry: StorageEntry): HTMLTableRowElement {
    const row = document.createElement("tr")
    row.className = "border-b border-zinc-100 last:border-0"
    row.innerHTML = `
      <td class="py-2 pr-2 font-mono text-zinc-800"></td>
      <td class="py-2 pr-2"></td>
      <td class="py-2 pr-2"></td>
      <td class="py-2 text-right"></td>
    `
    const keyCell = row.children.item(0)
    const typeCell = row.children.item(1)
    const valueCell = row.children.item(2)
    const actionsCell = row.children.item(3)
    if (keyCell) keyCell.textContent = String(entry.key)

    const type = document.createElement("select")
    type.className = "ide-select min-w-[5.5rem] w-full rounded border border-zinc-300 bg-white py-1 pl-2 text-xs"
    type.innerHTML = `<option value="string">String</option><option value="int">Int</option>`
    type.value = entry.type
    if (typeCell) typeCell.append(type)

    const value = document.createElement("input")
    value.type = "text"
    value.value = entry.value
    value.className = "w-full rounded border border-zinc-300 px-2 py-1 text-xs"
    if (valueCell) valueCell.append(value)

    const save = document.createElement("button")
    save.type = "button"
    save.className = "rounded bg-blue-600 px-2 py-1 text-[11px] font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
    save.textContent = "Save"
    save.addEventListener("click", () => this.saveStorageEntry(entry.key, type.value as "string" | "int", value.value))

    const del = document.createElement("button")
    del.type = "button"
    del.className = "ml-2 rounded bg-rose-100 px-2 py-1 text-[11px] font-semibold text-rose-800 hover:bg-rose-200 disabled:cursor-not-allowed disabled:opacity-50"
    del.textContent = "Delete"
    del.addEventListener("click", () => this.deleteStorageEntry(entry.key))

    if (actionsCell) actionsCell.append(save, del)
    return row
  }

  async copyFeedbackReport(): Promise<void> {
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

    if (this.watchFault) {
      lines.push("## Watch fault")
      lines.push(`Headline: ${this.watchFault.headline}`)
      lines.push(`Detail: ${this.watchFault.detail}`)
      lines.push(`Kind: ${this.watchFault.kind}`)
      lines.push("")
    }

    if (this.session?.ping_path) {
      lines.push("## Session (live ping)")
      try {
        const info = await postJSON(this.session.ping_path)
        lines.push(JSON.stringify(this.redactSession(info), null, 2))
      } catch (error) {
        lines.push(`Ping failed: ${errMessage(error)}`)
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
      await this.writeClipboardText(text)
      if (this.status) this.status.textContent = "Copied emulator feedback report to clipboard"
      this.appendLog("Copied emulator feedback report to clipboard", {
        flushTransfers: false,
        flushSystemLogs: false
      })
    } catch (error) {
      this.downloadFeedbackReport(text)
      this.setStatus(
        `Clipboard blocked; downloaded feedback report (${errMessage(error)})`
      )
      this.appendLog(`Downloaded emulator feedback report (${errMessage(error)})`, {
        flushTransfers: false,
        flushSystemLogs: false
      })
    }
  }

  async writeClipboardText(text: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(text)
    } catch (error) {
      if (!window.isSecureContext) throw error

      const target = document.createElement("textarea")
      target.setAttribute("readonly", "")
      target.style.cssText = "position: fixed; left: -10000px; top: 10px"
      target.value = text
      document.body.appendChild(target)
      target.focus()
      target.select()

      try {
        if (!document.execCommand("copy")) throw error
      } finally {
        target.remove()
      }
    }
  }

  downloadFeedbackReport(text: string): void {
    const slug = this.el.dataset.projectSlug || "emulator"
    const stamp = new Date().toISOString().replace(/[:.]/g, "-")
    const blob = new Blob([text], {type: "text/plain;charset=utf-8"})
    const url = URL.createObjectURL(blob)
    const link = document.createElement("a")
    link.href = url
    link.download = `${slug}-emulator-feedback-${stamp}.txt`
    link.style.display = "none"
    document.body.appendChild(link)
    link.click()
    link.remove()
    window.setTimeout(() => URL.revokeObjectURL(url), 0)
  }

  formatInstallationStatus(): string {
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

  formatVncSessionProbeState(): string {
    const probe = this.vncSessionProbe
    if (!probe) return "(none)"
    if (!probe.ok) return `failed in ${probe.ms}ms (${probe.error})`
    return `ok in ${probe.ms}ms (alive=${probe.alive}, display_ready=${probe.display_ready})`
  }

  formatLastQemuSettingsApply(): string {
    const apply = this.lastQemuSettingsApply
    if (!apply) return "(none)"
    const names = Array.isArray(apply.protocols)
      ? apply.protocols.map(p => String(p)).join(", ")
      : ""
    return `count=${apply.count ?? 0}, source=${apply.source ?? "?"}` + (names ? `, protocols=${names}` : "")
  }

  formatVncWebSocketState(): string {
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

  formatClientState(): string {
    const screen = this.expectedScreenSize()
    const vncBacking = this.readVncBackingSize()
    const phoneState =
      this.phoneSocket == null
        ? "none"
        : ["connecting", "open", "closing", "closed"][this.phoneSocket.readyState] || String(this.phoneSocket.readyState)

    const faultLines = this.watchFault
      ? [`Watch fault: ${this.watchFault.headline}`, `Watch fault detail: ${this.watchFault.detail}`]
      : ["Watch fault: (none)"]

    return [
      ...faultLines,
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

  redactSession(session: unknown): unknown {
    if (!session || typeof session !== "object") return session
    const copy = {...(session as Record<string, unknown>)}
    if (copy.token) copy.token = "(redacted)"
    return copy
  }

  async captureScreenshot(): Promise<void> {
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

      const slug = this.el.dataset.projectSlug ?? "default"
      const result = await postJSON<{screenshot?: string}>(
        `/api/emulator/projects/${encodeURIComponent(slug)}/screenshot`,
        {
        platform: this.el.dataset.emulatorTarget || "basalt",
        image
      })

      if (result.screenshot) {
        this.hook.pushEvent("wasm-screenshot-saved", {screenshot: result.screenshot})
      }

      this.setStatus("Saved embedded emulator screenshot")
    } catch (error) {
      this.setStatus(`Could not save embedded emulator screenshot: ${errMessage(error)}`)
    }
  }

  schedulePingAfterDisplayConnect(): void {
    return this.sessionClient.schedulePingAfterDisplayConnect()
  }

  stopPingAfterDisplayTimer(): void {
    if (this.pingAfterDisplayTimer) window.clearTimeout(this.pingAfterDisplayTimer)
    this.pingAfterDisplayTimer = null
  }

  startPing(): void {
    return this.sessionClient.startPing()
  }

  stopPing(): void {
    if (this.pingTimer) window.clearInterval(this.pingTimer)
    this.pingTimer = null
  }

  async pingSession(): Promise<void> {
    return this.sessionClient.pingSession()
  }

  targetScreenSize(): EmulatorScreen {
    const width = parseInt(this.el.dataset.emulatorScreenWidth || "144", 10)
    const height = parseInt(this.el.dataset.emulatorScreenHeight || "168", 10)
    return {width, height}
  }

  expectedScreenSize(): EmulatorScreen {
    const target = this.targetScreenSize()
    const sessionScreen = this.session?.screen
    if (!sessionScreen?.width || !sessionScreen?.height) return target
    if (sessionScreen.width !== target.width || sessionScreen.height !== target.height) return target
    return {width: sessionScreen.width, height: sessionScreen.height}
  }

  displayShape(): "round" | "rect" {
    const shape = this.el.dataset.emulatorDisplayShape
    return shape === "round" ? "round" : "rect"
  }

  cropCanvasToScreen(canvas: HTMLCanvasElement, screen: EmulatorScreen): string {
    const crop = document.createElement("canvas")
    crop.width = screen.width
    crop.height = screen.height
    const ctx = crop.getContext("2d")
    if (!ctx) return canvas.toDataURL("image/png")
    ctx.imageSmoothingEnabled = false
    ctx.drawImage(canvas, 0, 0, canvas.width, canvas.height, 0, 0, screen.width, screen.height)
    return crop.toDataURL("image/png")
  }

  selectedEmulatorTarget(): string | undefined {
    const target = this.el.dataset.emulatorTarget?.trim()
    return target || undefined
  }

  sessionTargetMismatch(): boolean {
    const selected = this.selectedEmulatorTarget()
    const sessionPlatform = this.session?.platform
    return !!(selected && sessionPlatform && sessionPlatform !== selected)
  }

  reconcileSessionWithSelectedTarget(): Promise<void> | undefined {
    if (!this.session || this.stopping || this.targetChangeStopInFlight || this.sessionEnded) return
    if (!this.sessionTargetMismatch()) return
    this.targetChangeStopInFlight = true
    return this.stopSessionForTargetChange().finally(() => {
      this.targetChangeStopInFlight = false
    })
  }

  async stopSessionForTargetChange(): Promise<void> {
    const previousPlatform = this.session?.platform
    const selected = this.selectedEmulatorTarget()
    if (!previousPlatform || !selected || previousPlatform === selected) return

    const message = `Watch model changed to ${selected}; stopped previous ${previousPlatform} session. Launch again to run on the selected model.`
    if (this.session) {
      await this.stop(message)
      return
    }

    this.endSession(message)
  }

  warnSessionScreenMismatch(): void {
    if (this.sessionTargetMismatch()) {
      const selected = this.selectedEmulatorTarget()
      this.appendLog(
        `emulator session platform ${this.session?.platform} differs from selected target ${selected}; relaunch required`
      )
      return
    }

    const target = this.targetScreenSize()
    const sessionScreen = this.session?.screen
    if (!sessionScreen?.width || !sessionScreen?.height) return
    if (sessionScreen.width === target.width && sessionScreen.height === target.height) return
    this.appendLog(
      `emulator session screen ${sessionScreen.width}x${sessionScreen.height} differs from selected target ${target.width}x${target.height}; using target size for display`
    )
  }

  logEmulatorPlatform(): void {
    const screen = this.expectedScreenSize()
    const platform = this.session?.platform || this.el.dataset.emulatorTarget || "unknown"
    this.appendLog(`Embedded emulator platform ${platform} (${screen.width}x${screen.height})`)
  }

  applyCanvasSize(): void {
    this.resizeCanvas(this.expectedScreenSize())
  }

  resizeCanvas(screen: EmulatorScreen): void {
    if (!this.canvas || !screen) return
    this.canvas.style.width = `${screen.width}px`
    this.canvas.style.height = `${screen.height}px`
    this.canvas.style.overflow = "hidden"
    this.canvas.style.display = "block"
    this.canvas.style.imageRendering = "pixelated"
    const innerCanvas = this.canvas.querySelector("canvas")
    if (innerCanvas) innerCanvas.style.imageRendering = "pixelated"
  }

  setStatus(message: string): void {
    this.currentStatus = message
    if (this.status) this.status.textContent = message
    this.appendLog(message)
  }

  appendLog(message: string, options: AppendLogOptions = {}): void {
    if (options.flushTransfers !== false) this.flushPutBytesSummary()
    if (options.flushSystemLogs !== false) this.flushSystemLogSummary()
    this.observeWatchFault(message)
    this.observeStorageLog(message)
    const stamp = `${new Date().toLocaleTimeString()} ${this.formatWatchFaultLogLine(message)}`
    const line =
      this.logLines.length === 0 && message.includes("Launching embedded emulator")
        ? `${stamp} [ui ${EMBEDDED_EMULATOR_UI_BUILD}]`
        : stamp
    this.logLines.unshift(line)
    this.logLines = this.logLines.slice(0, MAX_LOG_LINES)
    this.scheduleLogFlush()
    this.notifyStateChanged()
  }

  scheduleLogFlush(): void {
    if (this.destroyed || !this.log || this.logFlushScheduled) return
    this.logFlushScheduled = true
    window.requestAnimationFrame(() => {
      this.logFlushScheduled = false
      this.renderLog()
    })
  }

  renderLog(): void {
    if (this.log) this.log.textContent = this.logLines.join("\n").slice(0, MAX_LOG_CHARS)
  }

  clearLog(): void {
    this.logLines = []
    this.suppressedPutBytesFrames = 0
    this.logFlushScheduled = false
    if (this.log) this.log.textContent = ""
    this.clearWatchFault()
    this.watchAppLogShippingEnabled = false
    this.notifyStateChanged()
  }

  formatWatchFaultLogLine(message: string): string {
    const fault = classifyWatchFault(message)
    if (!fault) return message
    return `⚠ ${fault.headline}: ${fault.detail}`
  }

  observeWatchFault(message: string): void {
    const fault = classifyWatchFault(message)
    if (!fault) return
    if (this.watchFault?.detail === fault.detail && this.watchFault?.headline === fault.headline) return
    this.reportWatchFault(fault)
  }

  reportWatchFault(fault: WatchFault): void {
    this.watchFault = fault
    this.currentStatus = fault.headline
    if (fault.elmcRcCode != null && Number.isFinite(fault.elmcRcCode) && fault.elmcRcCode > 0) {
      this.hook.pushEvent("emulator-elmc-rc-fail", {
        code: fault.elmcRcCode,
        line: fault.elmcRcLine ?? 0
      })
    }
    if (this.status) {
      this.status.textContent = fault.headline
      this.status.classList.remove("bg-white", "text-zinc-700")
      this.status.classList.add("bg-rose-100", "text-rose-900", "ring-1", "ring-rose-400", "font-semibold")
    }
    if (this.faultBanner) {
      this.faultBanner.hidden = false
      if (this.faultHeadline) this.faultHeadline.textContent = fault.headline
      if (this.faultDetail) this.faultDetail.textContent = fault.detail
    }
    this.notifyStateChanged()
  }

  clearWatchFault(): void {
    this.watchFault = null
    if (this.status) {
      this.status.classList.add("bg-white", "text-zinc-700")
      this.status.classList.remove("bg-rose-100", "text-rose-900", "ring-1", "ring-rose-400", "font-semibold")
    }
    if (this.faultBanner) this.faultBanner.hidden = true
    if (this.faultHeadline) this.faultHeadline.textContent = ""
    if (this.faultDetail) this.faultDetail.textContent = ""
  }

  endSession(message: string): void {
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
    this.phoneCompanionCacheInstalled = false
    this.phoneCompanionInstalledAt = 0
    this.phoneBridgeReconnectInFlight = false
    this.phoneBridgeReconnectAttempts = 0
    this.phoneBridgeReconnectWindowStartedAt = 0
    this.phoneBridgeLastReconnectedAt = 0
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

  configurationResponseFromQuery(query: string): string {
    const params = new URLSearchParams(query || "")
    const response = params.get("response")
    return response === null ? (query || "") : response
  }

  hexPreview(bytes: Uint8Array, max = 24): string {
    const shown = Array.from(bytes.slice(0, max), (byte: number) => byte.toString(16).padStart(2, "0")).join(" ")
    return bytes.length > max ? `${shown} ...` : shown
  }

  truncate(value: string, max: number): string {
    if (value.length <= max) return value
    return `${value.slice(0, max)}...`
  }

  updateControlButtons(): void {
    this.launchButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-launch]")
    this.installButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-install]")
    this.preferencesButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-preferences]")
    this.screenshotButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-screenshot]")
    this.storageResetButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-storage-reset]")
    this.storageAddButton = this.el.querySelector<HTMLButtonElement>("[data-emulator-storage-add]")

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

  launchButtonLabel(): string {
    if (this.launching) return "Launching..."
    if (this.stopping) return "Stopping..."
    return this.session ? "Stop" : "Launch"
  }

  installReady(): boolean {
    return !!(
      this.session?.backend_enabled &&
      this.session?.install_path &&
      !this.sessionEnded &&
      this.sessionAlive &&
      !this.launching &&
      !this.stopping &&
      !this.sessionTargetMismatch()
    )
  }

  companionPreferencesReady(): boolean {
    return !!(this.session?.has_companion_preferences && this.session?.backend_enabled)
  }

  canCaptureScreenshot(): boolean {
    return !!this.canvas?.querySelector("canvas")
  }

  setButtonDisabled(button: HTMLButtonElement | null, disabled: boolean): void {
    if (!button) return
    button.disabled = disabled
    button.setAttribute("aria-disabled", disabled ? "true" : "false")
  }
}
