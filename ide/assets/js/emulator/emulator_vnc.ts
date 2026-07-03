import type {Channel} from "phoenix"
import type RFB from "@novnc/novnc"
import {getUserSocket, waitForUserSocketOpen} from "../user_socket"
import {postJSON} from "./emulator_http"
import type {EmulatorVncHost, VncSessionProbe} from "../types/emulator_host"
import type {EmulatorSessionInfo, PingResponse} from "../types/emulator"
import {errMessage} from "../types/errors"
import {
  computeVncViewportOffset,
  vncViewportConfigKey,
  vncViewportMode
} from "./vnc_viewport_crop"
import {correctVncCanvasColours, platformNeedsVncColourCorrection} from "./pebble_vnc_colours"

export type {EmulatorVncHost}

const PHOENIX_SOCKET_OPEN_TIMEOUT_MS = 10_000
const VNC_CHANNEL_JOIN_TIMEOUT_MS = 10_000
const VNC_WS_OPEN_TIMEOUT_MS = 10_000
const VNC_CONNECT_TIMEOUT_MS = 12_000
const VNC_RECONNECT_BASE_MS = 150
const VNC_RECONNECT_MAX_MS = 3_000
const DISPLAY_READY_TIMEOUT_MS = 90_000
const DISPLAY_READY_POLL_MS = 50

type VncChannelJoinOk = {
  initial?: string
}

type ChannelBinaryPayload =
  | ArrayBuffer
  | ArrayBufferView
  | string
  | {b64?: string}
  | null
  | undefined

type VncFrameSink = (data: ArrayBuffer) => void

type VncChannelTransport = {
  binaryType: BinaryType
  protocol: string
  bufferedAmount: number
  readyState: number
  send: (data: ArrayBuffer | ArrayBufferView) => void
  close: () => void
  onopen: ((this: WebSocket, ev: Event) => unknown) | null
  onmessage: ((this: WebSocket, ev: MessageEvent<ArrayBuffer>) => unknown) | null
  onerror: ((this: WebSocket, ev: Event) => unknown) | null
  onclose: ((this: WebSocket, ev: CloseEvent) => unknown) | null
}

type ScreenSize = {
  width: number
  height: number
}

type VncCanvasSample = {
  label: string
  sessionId: string | undefined
  wrapperPresent: boolean
  innerCanvasPresent: boolean
  wrapperSize: ScreenSize | null
  innerSize: ScreenSize | null
  backingSize: ScreenSize | null
  wrapperChildren: string[]
  pixelSample?: number[][]
  nonBlackSamples?: number
  uniqueGridColors?: string[]
  uniqueGridColorCount?: number
  pixelError?: string
}

let rfbModulePromise: Promise<typeof RFB> | null = null

export function loadRFB(): Promise<typeof RFB> {
  if (!rfbModulePromise) {
    rfbModulePromise = import("@novnc/novnc")
      .then(module => module.default)
      .catch((error: unknown) => {
        rfbModulePromise = null
        const message = errMessage(error)
        const blocked = message.includes("Failed to fetch") || error instanceof TypeError
        const hint = blocked
          ? " (check browser console for COEP/CORP blocked script — hard refresh after server restart)"
          : ""
        throw new Error(`Could not load noVNC display client${hint}: ${message}`)
      })
  }
  return rfbModulePromise
}

function vncWebSocketReadyStateLabel(readyState: number | null | undefined): string {
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

export class EmulatorVnc {
  private colourCorrectionRaf = 0

  constructor(host: EmulatorVncHost) {
    this.host = host
  }

  host: EmulatorVncHost

  closeVncSocket(): void {
    const ws = this.host.vncSocket
    if (ws) {
      try {
        ws.close()
      } catch {
        // Socket may already be closed.
      }
      this.host.vncSocket = null
    }
  }

  closeVncChannel(): void {
    if (this.host.vncChannel) {
      try {
        this.host.vncChannel.leave()
      } catch (_error) {
        // Channel may already be closed.
      }
      this.host.vncChannel = null
    }
    this.resetVncFramePipeline()
    this.host.vncPhoenixSocket = null
  }

  disconnectRfb(rfb: RFB | null | undefined, {reconnecting = false}: {reconnecting?: boolean} = {}): void {
    this.stopColourCorrection()
    if (reconnecting) this.host.reconnectingVnc = true
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

  stopColourCorrection(): void {
    if (this.colourCorrectionRaf) window.cancelAnimationFrame(this.colourCorrectionRaf)
    this.colourCorrectionRaf = 0
  }

  startColourCorrection(): void {
    this.stopColourCorrection()
    const platform = this.host.session?.platform || this.host.el.dataset.emulatorTarget
    if (!platformNeedsVncColourCorrection(platform)) return

    const tick = () => {
      if (this.host.destroyed) return
      const innerCanvas = this.host.canvas?.querySelector("canvas")
      if (innerCanvas instanceof HTMLCanvasElement && innerCanvas.width > 0) {
        correctVncCanvasColours(innerCanvas)
      }
      this.colourCorrectionRaf = window.requestAnimationFrame(tick)
    }

    this.colourCorrectionRaf = window.requestAnimationFrame(tick)
  }

  ensurePhoenixSocket(): ReturnType<typeof getUserSocket> {
    const socket = getUserSocket({onLog: message => this.host.appendLog(message)})
    this.host.vncPhoenixSocket = socket
    return socket
  }

  decodeChannelBinary(payload: ChannelBinaryPayload): ArrayBuffer | null {
    if (payload instanceof ArrayBuffer) return payload
    if (ArrayBuffer.isView(payload)) {
      return payload.buffer.slice(payload.byteOffset, payload.byteOffset + payload.byteLength)
    }
    if (payload && typeof payload === "object") {
      const encoded = payload.b64
      if (typeof encoded === "string") return this.base64ToArrayBuffer(encoded)
    }
    if (typeof payload === "string") {
      return this.base64ToArrayBuffer(payload)
    }
    return null
  }

  base64ToArrayBuffer(encoded: string): ArrayBuffer {
    const binary = atob(encoded)
    const bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i)
    return bytes.buffer
  }

  vncBytes(data: ArrayBuffer | ArrayBufferView): Uint8Array {
    if (data instanceof ArrayBuffer) return new Uint8Array(data)
    if (ArrayBuffer.isView(data)) {
      return new Uint8Array(data.buffer, data.byteOffset, data.byteLength)
    }
    throw new Error(`unsupported VNC frame data (${typeof data})`)
  }

  bytesToBase64(bytes: Uint8Array): string {
    let binary = ""
    const chunk = 0x8000
    for (let i = 0; i < bytes.length; i += chunk) {
      binary += String.fromCharCode(...bytes.subarray(i, i + chunk))
    }
    return btoa(binary)
  }

  pushVncFrame(channel: Channel, data: ArrayBuffer | ArrayBufferView): void {
    const bytes = this.vncBytes(data)
    if (!this.host.vncLoggedFirstSend) {
      this.host.vncLoggedFirstSend = true
      this.host.appendLog(`Embedded emulator VNC pushing ${bytes.length} byte(s) to channel`)
    }
    channel.push("frame", {b64: this.bytesToBase64(bytes)})
  }

  resetVncFramePipeline(): void {
    this.host.vncPendingFrames = []
    this.host.vncFrameSink = null
    this.host.vncJoinInitial = null
  }

  enqueueVncChannelFrame(payload: unknown): void {
    const data = this.decodeChannelBinary(payload as ChannelBinaryPayload)
    if (!data) {
      const kind =
        payload == null
          ? "null"
          : payload instanceof Object
            ? payload.constructor.name
            : typeof payload
      this.host.appendLog(`Embedded emulator VNC ignored frame payload (${kind})`)
      return
    }
    const chunkBytes = data.byteLength || 0
    const diag = this.host.vncWsDiag
    if (diag) {
      diag.bytesReceived = (diag.bytesReceived ?? 0) + chunkBytes
      diag.framesReceived = (diag.framesReceived ?? 0) + 1
    }
    if (this.host.vncFrameSink) {
      this.host.vncFrameSink(data)
    } else {
      this.host.vncPendingFrames.push(data)
    }
  }

  bindVncFrameSink(deliver: VncFrameSink): void {
    this.host.vncFrameSink = deliver
    const pending = this.host.vncPendingFrames
    this.host.vncPendingFrames = []
    for (const data of pending) deliver(data)
  }

  deliverVncJoinInitial(rfb: RFB): void {
    const data = this.host.vncJoinInitial
    if (!data || !rfb?._sock?._recvMessage) return

    this.host.vncJoinInitial = null
    rfb._sock._recvMessage({data})
    this.host.appendLog(`Embedded emulator delivered ${data.byteLength} byte(s) join initial to noVNC`)
  }

  async joinVncChannel(): Promise<Channel> {
    const sessionId = this.host.session?.id
    if (!sessionId) {
      throw new Error("Cannot join VNC channel: no emulator session id")
    }

    const socket = this.ensurePhoenixSocket()
    const topic = `emulator_vnc:${sessionId}`

    this.host.appendLog(`Opening Phoenix user socket (state=${socket.connectionState()})`)
    await waitForUserSocketOpen(socket, PHOENIX_SOCKET_OPEN_TIMEOUT_MS, {
      onLog: message => this.host.appendLog(message)
    })
    this.host.appendLog("Phoenix user socket open; joining emulator VNC channel")

    this.resetVncFramePipeline()
    const channel = socket.channel(topic, {})
    // Register before join: the server may push the RFB banner as soon as the relay starts.
    channel.on("frame", payload => this.enqueueVncChannelFrame(payload))

    return new Promise<Channel>((resolve, reject) => {
      let settled = false
      const finish = (error: Error | null, joinedChannel: Channel | null = null) => {
        if (settled) return
        settled = true
        window.clearTimeout(timer)
        if (error) reject(error)
        else if (joinedChannel) resolve(joinedChannel)
        else reject(new Error("Phoenix channel join finished without a channel"))
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
          const joinResponse = response as VncChannelJoinOk
          if (joinResponse.initial) {
            try {
              const binary = atob(joinResponse.initial)
              const bytes = new Uint8Array(binary.length)
              for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i)
              // Hold until noVNC has attached the transport and run _socketOpen(); feeding the
              // RFB banner earlier triggers "Unknown init state" and the handshake never starts.
              this.host.vncJoinInitial = bytes.buffer
              const diag = this.host.vncWsDiag
              if (diag) diag.bytesReceived = (diag.bytesReceived ?? 0) + bytes.byteLength
              this.host.appendLog(
                `Embedded emulator VNC channel received ${bytes.byteLength} byte(s) in join reply (held for noVNC init)`
              )
            } catch (error: unknown) {
              this.host.appendLog(`Embedded emulator VNC join initial decode failed: ${errMessage(error)}`)
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

  createVncChannelTransport(channel: Channel): VncChannelTransport {
    let onopen: VncChannelTransport["onopen"] = null
    let onmessage: VncChannelTransport["onmessage"] = null
    let onerror: VncChannelTransport["onerror"] = null
    let onclose: VncChannelTransport["onclose"] = null
    const pendingForTransport: ArrayBuffer[] = []

    const deliverToTransport = (data: ArrayBuffer) => {
      if (onmessage) onmessage.call({} as WebSocket, {data} as MessageEvent<ArrayBuffer>)
      else pendingForTransport.push(data)
    }

    const flushPendingForTransport = () => {
      if (!onmessage || pendingForTransport.length === 0) return
      const pending = pendingForTransport.splice(0)
      for (const data of pending) onmessage.call({} as WebSocket, {data} as MessageEvent<ArrayBuffer>)
    }

    this.bindVncFrameSink(deliverToTransport)

    channel.onError(() => {
      const diag = this.host.vncWsDiag
      if (diag) diag.error = "phoenix channel error"
      if (onerror) onerror.call({} as WebSocket, new Event("error"))
    })

    channel.onClose(() => {
      const diag = this.host.vncWsDiag
      if (diag) {
        diag.closed = true
        diag.open = false
      }
      if (onclose) onclose.call({} as WebSocket, new CloseEvent("close"))
    })

    return {
      binaryType: "arraybuffer",
      protocol: "",
      bufferedAmount: 0,
      readyState: WebSocket.OPEN,
      send: (data: ArrayBuffer | ArrayBufferView) => {
        this.pushVncFrame(channel, data)
      },
      close: () => {
        channel.leave()
      },
      get onopen() {
        return onopen
      },
      set onopen(fn: VncChannelTransport["onopen"]) {
        onopen = fn
      },
      get onmessage() {
        return onmessage
      },
      set onmessage(fn: VncChannelTransport["onmessage"]) {
        onmessage = fn
        flushPendingForTransport()
      },
      get onerror() {
        return onerror
      },
      set onerror(fn: VncChannelTransport["onerror"]) {
        onerror = fn
      },
      get onclose() {
        return onclose
      },
      set onclose(fn: VncChannelTransport["onclose"]) {
        onclose = fn
      }
    }
  }

  resetVncWsDiag(): void {
    this.host.vncLoggedFirstSend = false
    this.host.vncWsDiag = {
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

  attachVncWebSocketDiagnostics(ws: WebSocket): void {
    if (!ws || ws.__elmPebbleVncDiag) return
    ws.__elmPebbleVncDiag = true

    const diag = this.host.vncWsDiag
    if (!diag) return

    const refreshReadyState = () => {
      diag.readyState = ws.readyState
      diag.readyStateLabel = vncWebSocketReadyStateLabel(ws.readyState)
    }

    refreshReadyState()

    ws.addEventListener("open", () => {
      refreshReadyState()
      diag.open = true
      this.host.appendLog("Embedded emulator VNC websocket open")
    })
    ws.addEventListener("message", (event: MessageEvent<ArrayBuffer | string>) => {
      const chunkBytes =
        event.data instanceof ArrayBuffer
          ? event.data.byteLength
          : typeof event.data === "string"
            ? event.data.length
            : 0
      diag.bytesReceived = (diag.bytesReceived ?? 0) + chunkBytes
      diag.framesReceived = (diag.framesReceived ?? 0) + 1
    })
    ws.addEventListener("error", () => {
      refreshReadyState()
      diag.error = "websocket error"
    })
    ws.addEventListener("close", (event: CloseEvent) => {
      refreshReadyState()
      diag.closed = true
      diag.closeCode = event.code
      diag.closeReason = event.reason || null
    })
  }

  async probeEmulatorSession(pingPath: string): Promise<VncSessionProbe> {
    const started = performance.now()

    try {
      const info = await postJSON<PingResponse>(pingPath)
      return {
        ok: true,
        ms: Math.round(performance.now() - started),
        alive: info.alive === true,
        display_ready: info.display_ready === true
      }
    } catch (error: unknown) {
      return {
        ok: false,
        ms: Math.round(performance.now() - started),
        error: errMessage(error)
      }
    }
  }

  openVncWebSocket(url: string): Promise<WebSocket> {
    this.resetVncWsDiag()
    const diag = this.host.vncWsDiag
    if (diag) diag.url = url
    this.closeVncSocket()

    return new Promise<WebSocket>((resolve, reject) => {
      let settled = false
      let ws: WebSocket

      const finish = (error: Error | null, socket: WebSocket | null = null) => {
        if (settled) return
        settled = true
        window.clearInterval(stateTimer)
        window.clearTimeout(openTimer)
        if (error) {
          this.closeVncSocket()
          reject(error)
        } else if (socket) {
          resolve(socket)
        } else {
          reject(new Error("WebSocket finished without a socket"))
        }
      }

      try {
        ws = new WebSocket(url)
      } catch (error: unknown) {
        finish(new Error(`WebSocket constructor failed: ${errMessage(error)}`))
        return
      }

      ws.binaryType = "arraybuffer"
      this.host.vncSocket = ws
      this.attachVncWebSocketDiagnostics(ws)

      const stateTimer = window.setInterval(() => {
        const wsDiag = this.host.vncWsDiag
        if (!wsDiag || ws !== this.host.vncSocket) return
        wsDiag.readyState = ws.readyState
        wsDiag.readyStateLabel = vncWebSocketReadyStateLabel(ws.readyState)
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

  resolveCanvas(): HTMLElement | null {
    const canvas = this.host.el.querySelector<HTMLElement>("[data-emulator-canvas]")
    this.host.canvas = canvas
    return canvas
  }

  async waitForDisplayReady(timeoutMs = DISPLAY_READY_TIMEOUT_MS): Promise<boolean> {
    if (!this.host.session?.backend_enabled) return true
    if (this.host.session.display_ready) return true

    const deadline = Date.now() + timeoutMs
    const pingPath = this.host.session.ping_path

    while (Date.now() < deadline) {
      if (this.host.destroyed || !this.host.session) return false

      try {
        const info = await postJSON<EmulatorSessionInfo>(pingPath)
        if (info.display_ready) {
          Object.assign(this.host.session, info)
          return true
        }
      } catch {
        // Session may still be booting QEMU/VNC.
      }

      await new Promise(resolve => window.setTimeout(resolve, DISPLAY_READY_POLL_MS))
    }

    return !!this.host.session?.display_ready
  }

  async connectDisplay(): Promise<void> {
    if (this.host.destroyed || !this.host.session?.backend_enabled) return

    for (let attempt = 0; attempt < 20 && !this.resolveCanvas(); attempt += 1) {
      await new Promise(resolve => window.requestAnimationFrame(resolve))
    }

    if (!this.host.canvas) {
      this.host.appendLog("Embedded emulator display element not found in the page")
      return
    }

    if (!this.host.session.display_ready) {
      await this.waitForDisplayReady(15_000)
    }

    this.host.appendLog(`Connecting embedded emulator display (${this.host.session.vnc_path})`)

    try {
      await this.connectVnc()
    } catch (error) {
      this.host.appendLog(`Embedded emulator display failed: ${errMessage(error)}`)
    }
  }

  async connectVnc(): Promise<void> {
    if (this.host.destroyed || !this.host.session?.backend_enabled || !this.host.canvas) return
    if (this.host.vncConnecting) return
    this.host.vncConnecting = true
    if (this.host.rfb) {
      const previousRfb = this.host.rfb
      this.host.rfb = null
      this.host.rfbCanvas = null
      this.disconnectRfb(previousRfb, {reconnecting: this.host.displayConnected})
    }
    if (this.host.destroyed || !this.host.session?.backend_enabled || !this.host.canvas) {
      this.host.vncConnecting = false
      return
    }
    let RFBClass: typeof RFB
    try {
      RFBClass = await loadRFB()
    } catch (error) {
      this.host.vncConnecting = false
      throw error
    }
    if (this.host.destroyed || !this.host.session?.backend_enabled || !this.host.canvas) {
      this.host.vncConnecting = false
      return
    }
    const sessionProbe = await this.probeEmulatorSession(this.host.session.ping_path)
    this.host.vncSessionProbe = sessionProbe
    if (sessionProbe.ok) {
      this.host.appendLog(
        `Embedded emulator session probe ok in ${sessionProbe.ms}ms (alive=${sessionProbe.alive}, display_ready=${sessionProbe.display_ready})`
      )
    } else {
      this.host.appendLog(`Embedded emulator session probe failed in ${sessionProbe.ms}ms: ${sessionProbe.error}`)
    }
    this.host.appendLog(
      `Connecting embedded emulator display via Phoenix channel (emulator_vnc:${this.host.session.id})`
    )
    this.resetVncWsDiag()
    let channel: Channel
    try {
      channel = await this.joinVncChannel()
      this.host.vncChannel = channel
      this.host.appendLog("Embedded emulator VNC channel joined")
    } catch (error: unknown) {
      this.host.vncConnecting = false
      this.host.appendLog(`Embedded emulator VNC channel failed: ${errMessage(error)}`)
      throw error
    }
    if (this.host.destroyed || !this.host.session?.backend_enabled || !this.host.canvas) {
      this.host.vncConnecting = false
      this.closeVncChannel()
      return
    }
    const transport = this.createVncChannelTransport(channel)
    const wsDiag = this.host.vncWsDiag
    const bytesReceived = wsDiag?.bytesReceived ?? 0
    const framesReceived = wsDiag?.framesReceived ?? 0
    if (wsDiag) {
      wsDiag.url = `phoenix:/socket/emulator_vnc:${this.host.session.id}`
      Object.assign(wsDiag, {
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
    }
    let rfb: RFB
    try {
      rfb = new RFBClass(this.host.canvas, transport, {
        shared: true,
        credentials: {password: ""}
      })
      this.deliverVncJoinInitial(rfb)
    } catch (error) {
      this.host.vncConnecting = false
      this.closeVncChannel()
      throw error
    }
    this.host.rfb = rfb
    this.host.rfbCanvas = this.host.canvas
    this.host.vncViewportConfigKey = null
    this.host.vncConnecting = false
    this.host.reconnectingVnc = false
    this.host.updateControlButtons()
  
    rfb.resizeSession = false
    const connectTimeout = window.setTimeout(() => {
      if (this.host.destroyed || rfb !== this.host.rfb || this.host.displayConnected) return
      const diag = this.host.vncWsDiag
      const wsState = diag?.readyStateLabel || "unknown"
      const wsHint = diag?.open
        ? (diag.bytesReceived ?? 0) > 0
          ? `VNC transport received ${diag.bytesReceived} bytes in ${diag.framesReceived} frame(s) but noVNC did not finish the handshake`
          : this.host.vncPendingFrames.length > 0
            ? `VNC transport has ${this.host.vncPendingFrames.length} buffered frame(s) waiting for noVNC`
            : "VNC transport open but no binary frames received from the server"
        : diag?.closed
          ? `VNC transport closed (code ${diag.closeCode ?? "?"}, state ${wsState})`
          : diag?.error
            ? `${diag.error} (state ${wsState})`
            : `VNC transport did not open (state ${wsState})`
      this.host.appendLog(
        `Embedded emulator display connect timed out (no VNC response within ${VNC_CONNECT_TIMEOUT_MS / 1000}s; ${wsHint})`
      )
      this.disconnectRfb(rfb, {reconnecting: true})
      if (this.host.session && !this.host.stopping) {
        this.scheduleVncReconnect("Embedded emulator display timed out; reconnecting...")
      }
    }, VNC_CONNECT_TIMEOUT_MS)
    rfb.addEventListener("credentialsrequired", () => {
      if (this.host.destroyed || rfb !== this.host.rfb) return
      try {
        rfb.sendCredentials({password: ""})
      } catch (error: unknown) {
        this.host.appendLog(`Embedded emulator display credentials failed: ${errMessage(error)}`)
      }
    })
    rfb.addEventListener("securityfailure", event => {
      if (this.host.destroyed || rfb !== this.host.rfb) return
      window.clearTimeout(connectTimeout)
      const reason = event.detail?.reason || "security failure"
      this.host.appendLog(`Embedded emulator display security failure: ${reason}`)
      this.disconnectRfb(rfb, {reconnecting: true})
      if (this.host.session && !this.host.stopping) {
        this.scheduleVncReconnect(`Embedded emulator display security failure; reconnecting...`)
      }
    })
    rfb.addEventListener("connectfailed", event => {
      if (this.host.destroyed || rfb !== this.host.rfb) return
      window.clearTimeout(connectTimeout)
      const reason = event.detail?.reason || "connect failed"
      this.host.appendLog(`Embedded emulator display connect failed: ${reason}`)
      this.disconnectRfb(rfb, {reconnecting: true})
      if (this.host.session && !this.host.stopping) {
        this.scheduleVncReconnect(`Embedded emulator display connect failed; reconnecting...`)
      }
    })
    rfb.addEventListener("connect", () => {
      if (this.host.destroyed) return
      if (rfb !== this.host.rfb) return
      window.clearTimeout(connectTimeout)
      this.stopVncReconnect()
      this.host.vncReconnectAttempts = 0
      this.startColourCorrection()
    
      this.scheduleVncViewportConfig(rfb, "connect", 100)
      this.scheduleVncViewportConfig(rfb, "connect_1s", 1000)
      this.scheduleVncViewportConfig(rfb, "connect_3s", 3000)
      this.scheduleVncCanvasSample("after_connect")
      this.scheduleVncCanvasSample("after_connect_1s", 1000)
      if (this.host.session && !this.host.stopping) {
        this.host.displayConnected = true
        this.host.setStatus("Embedded emulator display connected")
        this.host.stopPingAfterDisplayTimer()
        if (!this.host.destroyed && !this.host.pingTimer) this.host.startPing()
        this.host.connectPhone()
      }
    })
    rfb.addEventListener("framebufferresize", () => {
      if (this.host.destroyed) return
      if (rfb !== this.host.rfb) return
      this.scheduleVncViewportConfig(rfb, "framebufferresize")
    })
    rfb.addEventListener("disconnect", event => {
      if (this.host.destroyed) return
      if (rfb !== this.host.rfb) return
      window.clearTimeout(connectTimeout)
      if (this.host.reconnectingVnc) return

      const detail = event.detail
      const status = detail?.status
      const clean = detail?.clean
      const reason = clean ? "clean disconnect" : `disconnect (status ${status ?? "?"})`
      if (this.host.session && !this.host.stopping) {
        this.host.appendLog(`Embedded emulator display ${reason}`)
        this.scheduleVncReconnect("Embedded emulator display disconnected; reconnecting...")
      }
    })
  }

  reconnectVncAfterDomPatch(): void {
    this.scheduleVncReconnect("Embedded emulator display moved; reconnecting...")
  }

  ensureVncAttached(): void {
    if (this.host.destroyed || !this.host.session?.backend_enabled || !this.host.canvas || this.host.stopping) return
    if (document.visibilityState === "hidden") return
    if (this.host.rfb && this.host.rfbCanvas === this.host.canvas) return
    if (this.host.vncReconnectTimer || this.host.reconnectingVnc || this.host.vncConnecting) return
    void this.connectDisplay()
  }

  scheduleVncReconnect(message: string): void {
    if (this.host.destroyed || !this.host.session?.backend_enabled || this.host.stopping || this.host.vncReconnectTimer) return
    this.host.setStatus(message)
    const delay = Math.min(VNC_RECONNECT_BASE_MS * 2 ** this.host.vncReconnectAttempts, VNC_RECONNECT_MAX_MS)
  
    this.host.vncReconnectAttempts += 1
    this.host.vncReconnectTimer = window.setTimeout(() => {
      this.host.vncReconnectTimer = null
      this.connectDisplay().catch((error: unknown) => {
        this.host.reconnectingVnc = false
        if (this.host.session && !this.host.stopping && !this.host.destroyed) {
          this.scheduleVncReconnect(`Embedded emulator display reconnect failed: ${errMessage(error)}`)
        }
      })
    }, delay)
  }

  stopVncReconnect(): void {
    if (this.host.vncReconnectTimer) window.clearTimeout(this.host.vncReconnectTimer)
    this.host.vncReconnectTimer = null
  }

  readVncBackingSize(): ScreenSize | null {
    const innerCanvas = this.host.canvas?.querySelector("canvas")
    if (!innerCanvas?.width || !innerCanvas?.height) return null
    return {width: innerCanvas.width, height: innerCanvas.height}
  }

  readVncFramebufferSize(rfb: RFB): ScreenSize | null {
    const fbWidth = rfb?._fbWidth ?? 0
    const fbHeight = rfb?._fbHeight ?? 0
    if (fbWidth > 0 && fbHeight > 0) {
      return {width: fbWidth, height: fbHeight}
    }
    return this.readVncBackingSize()
  }

  scheduleVncViewportConfig(rfb: RFB, reason: string, delayMs = 100): void {
    window.setTimeout(() => {
      if (this.host.destroyed || rfb !== this.host.rfb) return
      window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => {
          this.configureVncDisplay(rfb, reason)
        })
      })
    }, delayMs)
  }

  configureVncDisplay(rfb: RFB, reason = "connect"): void {
    if (this.host.destroyed || !rfb || rfb !== this.host.rfb || !this.host.canvas) return

    const screen = this.host.expectedScreenSize()
    this.host.applyCanvasSize()
    rfb.resizeSession = false

    const framebufferSize = this.readVncFramebufferSize(rfb)
    const canvasBacking = this.readVncBackingSize()
    const fbWidth = framebufferSize?.width ?? 0
    const fbHeight = framebufferSize?.height ?? 0
    const shape = this.host.displayShape()
    const framebuffer = {width: fbWidth, height: fbHeight}
    const mode = vncViewportMode(framebuffer, screen, shape)
    const offset = computeVncViewportOffset(framebuffer, screen, shape, mode)
    const configKey = vncViewportConfigKey(framebuffer, screen, mode, offset)
    const refreshFramebuffer = this.shouldRequestVncFramebufferRefresh(reason)
    const forceReapply = /framebufferresize/i.test(reason)
    const configUnchanged = this.host.vncViewportConfigKey === configKey

    if (configUnchanged && !forceReapply) {
      if (refreshFramebuffer) {
        this.requestVncFramebufferRefresh(rfb, fbWidth, fbHeight, reason)
      }
      return
    }

    this.host.vncViewportConfigKey = configKey

    if (mode === "scale") {
      // Some round QEMU builds expose a padded VNC buffer larger than the logical
      // panel. Fit the whole buffer into the watch frame instead of center-cropping,
      // which clips origin-aligned watchfaces on the left and right.
      rfb.scaleViewport = true
      rfb.clipViewport = false
    } else {
      rfb.scaleViewport = false
      rfb.clipViewport = true
      this.applyVncViewportOffset(rfb, offset)
    }

    const canvasNote =
      canvasBacking && (canvasBacking.width !== fbWidth || canvasBacking.height !== fbHeight)
        ? ` canvas ${canvasBacking.width}x${canvasBacking.height}`
        : ""
    const offsetNote = mode === "clip" && (offset.x > 0 || offset.y > 0) ? ` offset ${offset.x},${offset.y}` : ""
    const modeNote = mode === "scale" ? " scale (fit padded fb)" : oversizedModeNote(framebuffer, screen)

    this.host.appendLog(
      `VNC viewport ${reason}: framebuffer ${fbWidth}x${fbHeight}, screen ${screen.width}x${screen.height}, ${modeNote}${offsetNote}${canvasNote}`,
      {flushTransfers: false, flushSystemLogs: false}
    )

    if (refreshFramebuffer) {
      this.requestVncFramebufferRefresh(rfb, fbWidth, fbHeight, reason)
    }

    if (platformNeedsVncColourCorrection(this.host.session?.platform || this.host.el.dataset.emulatorTarget)) {
      const innerCanvas = this.host.canvas?.querySelector("canvas")
      if (innerCanvas instanceof HTMLCanvasElement) {
        correctVncCanvasColours(innerCanvas)
      }
    }
  }

  shouldRequestVncFramebufferRefresh(reason: string): boolean {
    return /install|app_start|framebufferresize|appmessage|draw_rendered|tick/i.test(reason)
  }

  applyVncViewportOffset(rfb: RFB, offset: {x: number; y: number}): void {
    const display = (rfb as unknown as {
      _display?: {viewportChangePos: (deltaX: number, deltaY: number) => void}
    })._display

    if (!display?.viewportChangePos) return

    if (offset.x > 0 || offset.y > 0) {
      display.viewportChangePos(offset.x, offset.y)
    }
  }

  requestVncFramebufferRefresh(rfb: RFB, width: number, height: number, reason: string): void {
    if (width <= 0 || height <= 0) return

    const connection = (rfb as unknown as {_rfb_connection?: {sendFramebufferUpdateRequest?: Function}})
      ._rfb_connection

    if (typeof connection?.sendFramebufferUpdateRequest !== "function") return

    try {
      connection.sendFramebufferUpdateRequest(false, 0, 0, width, height)
      this.host.appendLog(`VNC framebuffer refresh (${reason}) ${width}x${height}`, {
        flushTransfers: false,
        flushSystemLogs: false
      })
    } catch (error: unknown) {
      this.host.appendLog(`VNC framebuffer refresh failed (${reason}): ${errMessage(error)}`, {
        flushTransfers: false,
        flushSystemLogs: false
      })
    }
  }

  scheduleVncCanvasSample(label: string, delayMs = 0): void {
    if (!this.host.emulatorDebugEnabled()) return
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

  logVncCanvasSample(label: string): void {
    const innerCanvas = this.host.canvas?.querySelector("canvas")
    const wrapperRect = this.host.canvas?.getBoundingClientRect?.()
    const innerRect = innerCanvas?.getBoundingClientRect?.()
    const sample: VncCanvasSample = {
      label,
      sessionId: this.host.session?.id,
      wrapperPresent: !!this.host.canvas,
      innerCanvasPresent: !!innerCanvas,
      wrapperSize: wrapperRect ? {width: wrapperRect.width, height: wrapperRect.height} : null,
      innerSize: innerRect ? {width: innerRect.width, height: innerRect.height} : null,
      backingSize: innerCanvas ? {width: innerCanvas.width, height: innerCanvas.height} : null,
      wrapperChildren: this.host.canvas ? Array.from(this.host.canvas.children).map(child => child.tagName) : []
    }

    if (innerCanvas?.width && innerCanvas?.height) {
      if (platformNeedsVncColourCorrection(this.host.session?.platform || this.host.el.dataset.emulatorTarget)) {
        correctVncCanvasColours(innerCanvas)
      }
      try {
        const context = innerCanvas.getContext("2d")
        if (!context) throw new Error("2d canvas context unavailable")
        const points: Array<[number, number]> = [
          [Math.floor(innerCanvas.width / 2), Math.floor(innerCanvas.height / 2)],
          [1, 1],
          [Math.max(innerCanvas.width - 2, 0), 1],
          [1, Math.max(innerCanvas.height - 2, 0)],
          [Math.max(innerCanvas.width - 2, 0), Math.max(innerCanvas.height - 2, 0)]
        ]
        const pixels = points.map(([x, y]) => Array.from(context.getImageData(x, y, 1, 1).data))
        sample.pixelSample = pixels
        sample.nonBlackSamples = pixels.filter(([r, g, b, a]) => a !== 0 && (r !== 0 || g !== 0 || b !== 0)).length
        const gridColors: string[] = []
        for (let y = 0; y < 5; y += 1) {
          for (let x = 0; x < 5; x += 1) {
            const px = Math.floor(((x + 0.5) * innerCanvas.width) / 5)
            const py = Math.floor(((y + 0.5) * innerCanvas.height) / 5)
            gridColors.push(Array.from(context.getImageData(px, py, 1, 1).data).slice(0, 3).join(","))
          }
        }
        sample.uniqueGridColors = Array.from(new Set(gridColors)).slice(0, 12)
        sample.uniqueGridColorCount = new Set(gridColors).size
      } catch (error: unknown) {
        sample.pixelError = errMessage(error)
      }
    }

    this.host.appendLog(`VNC canvas sample ${label}: ${JSON.stringify(sample)}`)
  }
}

function oversizedModeNote(framebuffer: ScreenSize, screen: ScreenSize): string {
  const padded =
    framebuffer.width > screen.width + 1 || framebuffer.height > screen.height + 1
  return padded ? "clip (padded fb)" : "clip"
}

