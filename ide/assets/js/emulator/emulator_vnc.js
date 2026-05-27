import {disconnectUserSocket, getUserSocket, waitForUserSocketOpen} from "../user_socket.js"
import {websocketURL} from "./emulator_http.js"

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

export class EmulatorVnc {
  constructor(host) {
    this.host = host
  }

      this.host.vncSocket = null
    }
  }

  closeVncChannel() {
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

  disconnectRfb(rfb, {reconnecting = false} = {}) {
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

  ensurePhoenixSocket() {
    const socket = getUserSocket({onLog: message => this.host.appendLog(message)})
    this.host.vncPhoenixSocket = socket
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
    if (!this.host.vncLoggedFirstSend) {
      this.host.vncLoggedFirstSend = true
      this.host.appendLog(`Embedded emulator VNC pushing ${bytes.length} byte(s) to channel`)
    }
    channel.push("frame", {b64: this.bytesToBase64(bytes)})
  }

  resetVncFramePipeline() {
    this.host.vncPendingFrames = []
    this.host.vncFrameSink = null
    this.host.vncJoinInitial = null
  }

  enqueueVncChannelFrame(payload) {
    const data = this.decodeChannelBinary(payload)
    if (!data) {
      const kind = payload == null ? "null" : payload?.constructor?.name || typeof payload
      this.host.appendLog(`Embedded emulator VNC ignored frame payload (${kind})`)
      return
    }
    const chunkBytes = data.byteLength || 0
    if (this.host.vncWsDiag) {
      this.host.vncWsDiag.bytesReceived += chunkBytes
      this.host.vncWsDiag.framesReceived += 1
    }
    if (this.host.vncFrameSink) {
      this.host.vncFrameSink(data)
    } else {
      this.host.vncPendingFrames.push(data)
    }
  }

  bindVncFrameSink(deliver) {
    this.host.vncFrameSink = deliver
    const pending = this.host.vncPendingFrames
    this.host.vncPendingFrames = []
    for (const data of pending) deliver(data)
  }

  deliverVncJoinInitial(rfb) {
    const data = this.host.vncJoinInitial
    if (!data || !rfb?._sock?._recvMessage) return

    this.host.vncJoinInitial = null
    rfb._sock._recvMessage({data})
    this.host.appendLog(`Embedded emulator delivered ${data.byteLength} byte(s) join initial to noVNC`)
  }

  async joinVncChannel() {
    const socket = this.ensurePhoenixSocket()
    const topic = `emulator_vnc:${this.host.session.id}`

    this.host.appendLog(`Opening Phoenix user socket (state=${socket.connectionState()})`)
    await waitForUserSocketOpen(socket, PHOENIX_SOCKET_OPEN_TIMEOUT_MS, {
      onLog: message => this.host.appendLog(message)
    })
    this.host.appendLog("Phoenix user socket open; joining emulator VNC channel")

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
              this.host.vncJoinInitial = bytes.buffer
              if (this.host.vncWsDiag) this.host.vncWsDiag.bytesReceived += bytes.byteLength
              this.host.appendLog(
                `Embedded emulator VNC channel received ${bytes.byteLength} byte(s) in join reply (held for noVNC init)`
              )
            } catch (error) {
              this.host.appendLog(`Embedded emulator VNC join initial decode failed: ${error.message}`)
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
      if (this.host.vncWsDiag) this.host.vncWsDiag.error = "phoenix channel error"
      if (onerror) onerror(new Event("error"))
    })

    channel.onClose(() => {
      if (this.host.vncWsDiag) {
        this.host.vncWsDiag.closed = true
        this.host.vncWsDiag.open = false
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

  attachVncWebSocketDiagnostics(ws) {
    if (!ws || ws.__elmPebbleVncDiag) return
    ws.__elmPebbleVncDiag = true

    const refreshReadyState = () => {
      this.host.vncWsDiag.readyState = ws.readyState
      this.host.vncWsDiag.readyStateLabel = vncWebSocketReadyStateLabel(ws.readyState)
    }

    refreshReadyState()

    ws.addEventListener("open", () => {
      refreshReadyState()
      this.host.vncWsDiag.open = true
      this.host.appendLog("Embedded emulator VNC websocket open")
    })
    ws.addEventListener("message", event => {
      const chunkBytes =
        event.data instanceof ArrayBuffer
          ? event.data.byteLength
          : typeof event.data === "string"
            ? event.data.length
            : 0
      this.host.vncWsDiag.bytesReceived += chunkBytes
      this.host.vncWsDiag.framesReceived += 1
    })
    ws.addEventListener("error", () => {
      refreshReadyState()
      this.host.vncWsDiag.error = "websocket error"
    })
    ws.addEventListener("close", event => {
      refreshReadyState()
      this.host.vncWsDiag.closed = true
      this.host.vncWsDiag.closeCode = event.code
      this.host.vncWsDiag.closeReason = event.reason || null
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
    this.host.vncWsDiag.url = url
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
      this.host.vncSocket = ws
      this.attachVncWebSocketDiagnostics(ws)

      const stateTimer = window.setInterval(() => {
        if (!this.host.vncWsDiag || ws !== this.host.vncSocket) return
        this.host.vncWsDiag.readyState = ws.readyState
        this.host.vncWsDiag.readyStateLabel = vncWebSocketReadyStateLabel(ws.readyState)
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
    let RFB
    try {
      RFB = await loadRFB()
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
    this.host.appendLog(`Connecting embedded emulator display via Phoenix channel (emulator_vnc:${this.host.session.id})`)
    this.resetVncWsDiag()
    let channel
    try {
      channel = await this.joinVncChannel()
      this.host.vncChannel = channel
      this.host.appendLog("Embedded emulator VNC channel joined")
    } catch (error) {
      this.host.vncConnecting = false
      this.host.appendLog(`Embedded emulator VNC channel failed: ${error.message}`)
      throw error
    }
    if (this.host.destroyed || !this.host.session?.backend_enabled || !this.host.canvas) {
      this.host.vncConnecting = false
      this.closeVncChannel()
      return
    }
    const transport = this.createVncChannelTransport(channel)
    const bytesReceived = this.host.vncWsDiag?.bytesReceived || 0
    const framesReceived = this.host.vncWsDiag?.framesReceived || 0
    this.host.vncWsDiag.url = `phoenix:/socket/emulator_vnc:${this.host.session.id}`
    Object.assign(this.host.vncWsDiag, {
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
      rfb = new RFB(this.host.canvas, transport, {
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
      const diag = this.host.vncWsDiag || {}
      const wsState = diag.readyStateLabel || "unknown"
      const wsHint = diag.open
        ? diag.bytesReceived > 0
          ? `VNC transport received ${diag.bytesReceived} bytes in ${diag.framesReceived} frame(s) but noVNC did not finish the handshake`
          : this.host.vncPendingFrames?.length > 0
            ? `VNC transport has ${this.host.vncPendingFrames.length} buffered frame(s) waiting for noVNC`
            : "VNC transport open but no binary frames received from the server"
        : diag.closed
          ? `VNC transport closed (code ${diag.closeCode ?? "?"}, state ${wsState})`
          : diag.error
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
      } catch (error) {
        this.host.appendLog(`Embedded emulator display credentials failed: ${error.message}`)
      }
    })
    rfb.addEventListener("securityfailure", event => {
      if (this.host.destroyed || rfb !== this.host.rfb) return
      window.clearTimeout(connectTimeout)
      const reason = event?.detail?.reason || "security failure"
      this.host.appendLog(`Embedded emulator display security failure: ${reason}`)
      this.disconnectRfb(rfb, {reconnecting: true})
      if (this.host.session && !this.host.stopping) {
        this.scheduleVncReconnect(`Embedded emulator display security failure; reconnecting...`)
      }
    })
    rfb.addEventListener("connectfailed", event => {
      if (this.host.destroyed || rfb !== this.host.rfb) return
      window.clearTimeout(connectTimeout)
      const reason = event?.detail?.reason || "connect failed"
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
    
      const detail = event?.detail
      const status = detail?.status
      const clean = detail?.clean
      const reason = clean ? "clean disconnect" : `disconnect (status ${status ?? "?"})`
      if (this.host.session && !this.host.stopping) {
        this.host.appendLog(`Embedded emulator display ${reason}`)
        this.scheduleVncReconnect("Embedded emulator display disconnected; reconnecting...")
      }
    })
  }

  reconnectVncAfterDomPatch() {
    this.scheduleVncReconnect("Embedded emulator display moved; reconnecting...")
  }

  ensureVncAttached() {
    if (this.host.destroyed || !this.host.session?.backend_enabled || !this.host.canvas || this.host.stopping) return
    if (document.visibilityState === "hidden") return
    if (this.host.rfb && this.host.rfbCanvas === this.host.canvas) return
    if (this.host.vncReconnectTimer || this.host.reconnectingVnc || this.host.vncConnecting) return
    void this.connectDisplay()
  }

  scheduleVncReconnect(message) {
    if (this.host.destroyed || !this.host.session?.backend_enabled || this.host.stopping || this.host.vncReconnectTimer) return
    this.host.setStatus(message)
    const delay = Math.min(VNC_RECONNECT_BASE_MS * 2 ** this.host.vncReconnectAttempts, VNC_RECONNECT_MAX_MS)
  
    this.host.vncReconnectAttempts += 1
    this.host.vncReconnectTimer = window.setTimeout(() => {
      this.host.vncReconnectTimer = null
      this.connectDisplay().catch(error => {
        this.host.reconnectingVnc = false
        if (this.host.session && !this.host.stopping && !this.host.destroyed) this.scheduleVncReconnect(`Embedded emulator display reconnect failed: ${error.message}`)
      })
    }, delay)
  }

  stopVncReconnect() {
    if (this.host.vncReconnectTimer) window.clearTimeout(this.host.vncReconnectTimer)
    this.host.vncReconnectTimer = null
  }

  readVncBackingSize() {
    const innerCanvas = this.host.canvas?.querySelector("canvas")
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
      if (this.host.destroyed || rfb !== this.host.rfb) return
      window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => {
          this.configureVncDisplay(rfb, reason)
        })
      })
    }, delayMs)
  }

  configureVncDisplay(rfb, reason = "connect") {
    if (this.host.destroyed || !rfb || rfb !== this.host.rfb || !this.host.canvas) return

    const screen = this.host.expectedScreenSize()
    this.host.applyCanvasSize()
    rfb.resizeSession = false

    const framebuffer = this.readVncFramebufferSize(rfb)
    const canvasBacking = this.readVncBackingSize()
    const fbWidth = framebuffer?.width ?? 0
    const fbHeight = framebuffer?.height ?? 0
    const oversized =
      fbWidth > screen.width + 1 ||
      fbHeight > screen.height + 1
    const configKey = `${fbWidth}x${fbHeight}:${screen.width}x${screen.height}`
    if (this.host.vncViewportConfigKey === configKey) return
    this.host.vncViewportConfigKey = configKey

    // Always clip at 1:1. scaleViewport scales the entire padded QEMU surface into
    // the canvas, which shrinks a top-left draw layer into the upper-left quadrant.
    rfb.scaleViewport = false
    rfb.clipViewport = true

    const canvasNote =
      canvasBacking && (canvasBacking.width !== fbWidth || canvasBacking.height !== fbHeight)
        ? ` canvas ${canvasBacking.width}x${canvasBacking.height}`
        : ""

    this.host.appendLog(
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
    const innerCanvas = this.host.canvas?.querySelector("canvas")
    const wrapperRect = this.host.canvas?.getBoundingClientRect?.()
    const innerRect = innerCanvas?.getBoundingClientRect?.()
    const sample = {
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

  
  }

  connectPhone() {
    if (this.host.destroyed || !this.host.session?.backend_enabled) return
    const oldPhoneSocket = this.host.phoneSocket
    this.host.phoneBridgeActive = true
    const socket = new WebSocket(websocketURL(this.host.session.phone_path))
    this.host.phoneSocket = socket
    if (oldPhoneSocket) oldPhoneSocket.close()
    socket.binaryType = "arraybuffer"
    socket.addEventListener("message", event => {
      if (this.host.destroyed || socket !== this.host.phoneSocket) return
      this.host.handlePhoneMessage(event)
    })
    socket.addEventListener("open", () => {
      if (this.host.destroyed || socket !== this.host.phoneSocket) return
      this.host.phoneOpenedAt = Date.now()
      this.host.phoneBridgeReady = true
      this.host.appendLog("phone websocket open")
      if (this.host.buttonState !== 0) this.host.sendQemu(QEMU.button, [this.host.buttonState])
    })
    socket.addEventListener("error", () => {
      if (this.host.destroyed || socket !== this.host.phoneSocket) return
      this.host.appendLog("phone websocket error")
    })
    socket.addEventListener("close", event => {
      if (this.host.destroyed || socket !== this.host.phoneSocket) return
      this.host.appendLog(`phone websocket closed (code ${event.code || "?"})`)
      this.host.phoneBridgeActive = false
      this.host.phoneBridgeReady = false
      if (this.host.session && !this.host.stopping && !this.host.installing && this.host.phoneOpenedAt > 0) {
        this.host.endSession("Embedded emulator phone bridge disconnected")
      }
    })
}
