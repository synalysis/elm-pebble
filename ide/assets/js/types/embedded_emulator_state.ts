import type RFB from "@novnc/novnc"
import type {EmulatorSessionInfo} from "./emulator"

export type StorageEntry = {
  key: number
  type: "string" | "int"
  value: string
  updatedAt: number
}

export type DataLogEntry = {
  command?: number
  session?: number
  uuid?: string
  timestamp?: number
  tagHex?: string
  itemType?: number
  itemSize?: number
  payloadPrefix?: string
  recordedAt?: number
}

export type PendingPypkjsInstall = {
  resolve: () => void
  reject: (reason?: Error) => void
  timeoutId: ReturnType<typeof setTimeout>
  promise: Promise<void>
}

/** Fields stored in window.__elmPebbleEmbeddedEmulatorStates per project key. */
export type EmbeddedEmulatorPersistedState = {
  key: string
  session: EmulatorSessionInfo | null
  buttonState: number
  launching: boolean
  installing: boolean
  appInstalled: boolean
  stopping: boolean
  pendingPypkjsInstall: PendingPypkjsInstall | null
  currentStatus: string | null
  logLines: string[]
  storageEntries: Map<string, StorageEntry>
  suppressedPutBytesFrames: number
  suppressedSystemLogFrames: number
  sessionEnded: boolean
  sessionAlive: boolean
  displayConnected: boolean
  phoneBridgeReady: boolean
  phoneBridgeActive: boolean
  dataLogEntries: DataLogEntry[]
  rfb: RFB | null
  rfbCanvas: HTMLElement | null
  vncConnecting: boolean
  reconnectingVnc: boolean
  vncReconnectTimer: ReturnType<typeof setTimeout> | null
  vncReconnectAttempts: number
}

export type EmbeddedEmulatorRuntimeState = EmbeddedEmulatorPersistedState & {
  listeners: Set<() => void>
}
