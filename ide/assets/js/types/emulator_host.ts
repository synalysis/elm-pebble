import type {Channel, Socket} from "phoenix"
import type RFB from "@novnc/novnc"
import type {EmulatorScreen, EmulatorSessionInfo, SimulatorSettings} from "./emulator"
import type {SimulatorSettingsOptions} from "./emulator_options"
import type {HookContext} from "./liveview_hook"

export type AppendLogOptions = {
  flushTransfers?: boolean
  flushSystemLogs?: boolean
}

export type VncSessionProbe = {
  ok: boolean
  ms: number
  alive?: boolean
  display_ready?: boolean
  error?: string
}

/** Surface shared by emulator VNC / session client / simulator delivery modules. */
export type EmbeddedEmulatorHostSurface = {
  el: HTMLElement
  hook: HookContext
  destroyed: boolean
  session: EmulatorSessionInfo | null
  sessionAlive: boolean
  displayConnected: boolean
  phoneBridgeReady: boolean
  phoneBridgeActive: boolean
  phoneCompanionCacheInstalled: boolean
  phoneCompanionInstalledAt: number
  phoneBridgeReconnectInFlight: boolean
  phoneBridgeReconnectAttempts: number
  phoneBridgeReconnectWindowStartedAt: number
  phoneBridgeLastReconnectedAt: number
  launching: boolean
  installing: boolean
  stopping: boolean
  appInstalled: boolean
  sessionEnded: boolean
  canvas: HTMLElement | null
  vncConnecting: boolean
  reconnectingVnc: boolean
  vncSocket: WebSocket | null
  vncChannel: Channel | null
  vncPhoenixSocket: Socket | null
  vncPendingFrames: ArrayBuffer[]
  vncFrameSink: ((data: ArrayBuffer) => void) | null
  vncJoinInitial: ArrayBuffer | null
  vncLoggedFirstSend: boolean
  vncWsDiag: VncWsDiag | null
  vncReconnectTimer: ReturnType<typeof setTimeout> | null
  vncReconnectAttempts: number
  vncViewportConfigKey: string | null
  vncViewportConfigTimer: ReturnType<typeof setTimeout> | null
  pingTimer: ReturnType<typeof setInterval> | null
  pingAfterDisplayTimer: ReturnType<typeof setTimeout> | null
  rfb: RFB | null
  rfbCanvas: HTMLElement | null
  vncSessionProbe: VncSessionProbe | null
  simulatorSettings: SimulatorSettings | null
  lastSentWeatherJson: string | null
  appendLog: (message: string, options?: AppendLogOptions) => void
  emulatorDebugEnabled: () => boolean
  setStatus: (message: string) => void
  endSession: (message: string) => void
  clearLog: () => void
  hideConfigPage: () => void
  notifyStateChanged: () => void
  warnSessionScreenMismatch: () => void
  logEmulatorPlatform: () => void
  applyCanvasSize: () => void
  expectedScreenSize: () => EmulatorScreen
  displayShape: () => "round" | "rect"
  connectPhone: () => void
  updateControlButtons: () => void
  startPing: () => void
  waitForDisplayReady: () => Promise<boolean>
  connectDisplay: () => Promise<void>
  schedulePingAfterDisplayConnect: () => void
  stopPingAfterDisplayTimer: () => void
  stopPing: () => void
  scheduleVncViewportConfig: (rfb: RFB, label: string, delayMs: number) => void
  ensureVncAttached: () => void
  reapplySimulatorSettingsToQemu: (options?: SimulatorSettingsOptions) => void
}

export type VncWsDiag = {
  url?: string | null
  open?: boolean
  closed?: boolean
  readyState?: number | null
  readyStateLabel?: string
  bytesReceived?: number
  framesReceived?: number
  bytesSent?: number
  framesSent?: number
  error?: string | null
  closeCode?: number | null
  closeReason?: string | null
}

export type EmulatorVncHost = EmbeddedEmulatorHostSurface
