const BUTTONS = {back: 0, up: 1, select: 2, down: 3}
const QEMU = {
  tap: 2,
  bluetooth: 3,
  battery: 5,
  button: 8,
  timeFormat: 9,
  timelinePeek: 10
}
const CONFIG_RETURN_PATH = "/api/emulator/config-return"
const MAX_LOG_LINES = 300
const MAX_LOG_CHARS = 40000
const PUTBYTES_SUMMARY_INTERVAL = 25
const PHONE_BRIDGE_INSTALL_TIMEOUT_MS = 120000
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
  typeInt: 1,
  typeString: 2
}

const csrfToken = () => document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
let rfbModulePromise = null

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
    this.rfb = null
    this.phoneSocket = null
    this.session = null
    this.buttonState = 0
    this.pingTimer = null
    this.configUrl = null
    this.configPopupTimer = null
    this.phoneOpenedAt = 0
    this.launching = false
    this.installing = false
    this.stopping = false
    this.pendingPypkjsInstall = null
    this.currentStatus = null
    this.logLines = []
    this.storageEntries = new Map()
    this.logFlushScheduled = false
    this.suppressedPutBytesFrames = 0
    this.sessionEnded = false
    this.rfbCanvas = null
    this.reconnectingVnc = false
    this.vncReconnectTimer = null
    this.vncReconnectAttempts = 0
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
    this.stopButton = this.el.querySelector("[data-emulator-stop]")
    this.storageRows = this.el.querySelector("[data-emulator-storage-rows]")
    this.storageResetButton = this.el.querySelector("[data-emulator-storage-reset]")
    this.storageAddButton = this.el.querySelector("[data-emulator-storage-add]")
    this.storageNewKey = this.el.querySelector("[data-emulator-storage-new-key]")
    this.storageNewType = this.el.querySelector("[data-emulator-storage-new-type]")
    this.storageNewValue = this.el.querySelector("[data-emulator-storage-new-value]")
    this.launchButton?.addEventListener("click", () => this.launch())
    this.stopButton?.addEventListener("click", () => this.stop())
    this.installButton?.addEventListener("click", () => this.install())
    this.preferencesButton?.addEventListener("click", () => this.loadCompanionPreferences())
    this.storageResetButton?.addEventListener("click", () => this.resetStorage())
    this.storageAddButton?.addEventListener("click", () => this.saveNewStorageEntry())
    this.el.querySelector("[data-emulator-screenshot]")?.addEventListener("click", () => this.captureScreenshot())
    this.el.querySelector("[data-emulator-config-cancel]")?.addEventListener("click", () => this.cancelConfig())
    this.configPanel?.addEventListener("click", event => {
      if (event.target === this.configPanel) this.cancelConfig()
    })
    this.configFrame?.addEventListener("load", () => this.maybeHandleConfigReturn(this.configFrame.contentWindow))
    document.addEventListener("keydown", this.handleConfigKeyDown)

    this.el.querySelectorAll("[data-emulator-button]").forEach(button => {
      const name = button.dataset.emulatorButton
      button.addEventListener("pointerdown", event => {
        event.preventDefault()
        this.pressButton(name, true)
      })
      button.addEventListener("pointerup", () => this.pressButton(name, false))
      button.addEventListener("pointerleave", () => this.pressButton(name, false))
    })

    this.el.querySelector("[data-emulator-battery]")?.addEventListener("input", event => {
      this.setBattery(parseInt(event.target.value || "80", 10), this.el.querySelector("[data-emulator-charging]")?.checked)
    })
    this.el.querySelector("[data-emulator-charging]")?.addEventListener("change", event => {
      const battery = parseInt(this.el.querySelector("[data-emulator-battery]")?.value || "80", 10)
      this.setBattery(battery, event.target.checked)
    })
    this.el.querySelector("[data-emulator-bluetooth]")?.addEventListener("change", event => this.sendQemu(QEMU.bluetooth, [event.target.checked ? 1 : 0]))
    this.el.querySelector("[data-emulator-24h]")?.addEventListener("change", event => this.sendQemu(QEMU.timeFormat, [event.target.checked ? 1 : 0]))
    this.el.querySelector("[data-emulator-peek]")?.addEventListener("change", event => this.sendQemu(QEMU.timelinePeek, [event.target.checked ? 1 : 0]))
    this.el.querySelector("[data-emulator-tap]")?.addEventListener("click", () => this.sendQemu(QEMU.tap, [0, 1]))
    this.updateControlButtons()
  }

  updated() {
    const previousCanvas = this.canvas
    this.canvas = this.el.querySelector("[data-emulator-canvas]")
    this.status = this.el.querySelector("[data-emulator-status]")
    this.log = this.el.querySelector("[data-emulator-log]")
    this.launchButton = this.el.querySelector("[data-emulator-launch]")
    this.installButton = this.el.querySelector("[data-emulator-install]")
    this.preferencesButton = this.el.querySelector("[data-emulator-preferences]")
    this.stopButton = this.el.querySelector("[data-emulator-stop]")
    this.storageRows = this.el.querySelector("[data-emulator-storage-rows]")
    this.storageResetButton = this.el.querySelector("[data-emulator-storage-reset]")
    this.storageAddButton = this.el.querySelector("[data-emulator-storage-add]")

    if (this.status && this.currentStatus) {
      this.status.textContent = this.currentStatus
    }
    this.renderLog()
    this.renderStorage()
    this.updateControlButtons()
    if (this.session?.backend_enabled && this.rfb && previousCanvas && previousCanvas !== this.canvas) {
      this.reconnectVncAfterDomPatch()
    }
  }

  destroy(removeListeners = true) {
    this.stopPing()
    this.stopVncReconnect()
    this.stopConfigPopupPolling()
    if (removeListeners) document.removeEventListener("keydown", this.handleConfigKeyDown)
    if (this.rfb) this.rfb.disconnect()
    if (this.phoneSocket) this.phoneSocket.close()
  }

  async launch() {
    if (this.launching || this.session) return
    this.launching = true
    this.updateControlButtons()

    try {
      this.clearLog()
      this.hideConfigPage()
      this.sessionEnded = false
      this.setStatus("Launching embedded emulator...")
      const payload = {
        slug: this.el.dataset.projectSlug,
        platform: this.el.dataset.emulatorTarget
      }
      this.session = await postJSON("/api/emulator/launch", payload)
      this.resizeCanvas(this.session.screen)
      await this.connectVnc()
      this.connectPhone()
      this.startPing()
      this.setStatus(this.session.backend_enabled ? "Embedded emulator connected" : "Embedded emulator backend disabled; launch API is in dry-run mode")
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
    if (!this.session.backend_enabled || !this.canvas) return
    if (this.rfb) {
      this.reconnectingVnc = true
      this.rfb.disconnect()
    }
    const RFB = await loadRFB()
    const rfb = new RFB(this.canvas, websocketURL(this.session.vnc_path), {shared: true})
    this.rfb = rfb
    this.rfbCanvas = this.canvas
    this.reconnectingVnc = false
    rfb.scaleViewport = true
    rfb.resizeSession = false
    rfb.addEventListener("connect", () => {
      if (rfb !== this.rfb) return
      this.stopVncReconnect()
      this.vncReconnectAttempts = 0
      if (this.session && !this.stopping) this.setStatus("Embedded emulator display connected")
    })
    rfb.addEventListener("disconnect", () => {
      if (rfb !== this.rfb) return
      if (this.reconnectingVnc) return
      if (this.session && !this.stopping) this.scheduleVncReconnect("Embedded emulator display disconnected; reconnecting...")
    })
  }

  reconnectVncAfterDomPatch() {
    this.scheduleVncReconnect("Embedded emulator display moved; reconnecting...")
  }

  scheduleVncReconnect(message) {
    if (!this.session?.backend_enabled || this.stopping || this.vncReconnectTimer) return
    this.setStatus(message)
    const delay = Math.min(500 * 2 ** this.vncReconnectAttempts, 5_000)
    this.vncReconnectAttempts += 1
    this.vncReconnectTimer = window.setTimeout(() => {
      this.vncReconnectTimer = null
      this.connectVnc().catch(error => {
        this.reconnectingVnc = false
        if (this.session && !this.stopping) this.scheduleVncReconnect(`Embedded emulator display reconnect failed: ${error.message}`)
      })
    }, delay)
  }

  stopVncReconnect() {
    if (this.vncReconnectTimer) window.clearTimeout(this.vncReconnectTimer)
    this.vncReconnectTimer = null
  }

  connectPhone() {
    if (!this.session.backend_enabled) return
    if (this.phoneSocket) this.phoneSocket.close()
    this.phoneSocket = new WebSocket(websocketURL(this.session.phone_path))
    this.phoneSocket.binaryType = "arraybuffer"
    this.phoneSocket.addEventListener("message", event => this.handlePhoneMessage(event))
    this.phoneSocket.addEventListener("open", () => {
      this.phoneOpenedAt = Date.now()
      this.appendLog("phone websocket open")
      window.setTimeout(() => this.enableAppLogs(), 250)
    })
    this.phoneSocket.addEventListener("close", () => {
      this.appendLog("phone websocket closed")
      if (this.session && !this.stopping) this.endSession("Embedded emulator phone bridge disconnected")
    })
  }

  async install() {
    if (this.installing || !this.session) return
    this.installing = true
    this.updateControlButtons()

    try {
      if (this.session?.has_phone_companion && this.phoneSocket?.readyState === WebSocket.OPEN && this.session?.artifact_path) {
        await this.installPbwViaPhoneBridge()
        return
      }
      if (!this.session?.install_path) {
        this.setStatus("Embedded emulator install API is unavailable.")
        return
      }
      this.setStatus("Installing PBW on embedded emulator via fallback installer...")
      const response = await postJSON(this.session.install_path)
      const parts = response.result?.parts?.map(part => part.kind).join(", ")
      this.setStatus(parts ? `PBW installed on embedded emulator (${parts})` : "PBW installed on embedded emulator")
      this.appendLog("native PBW install complete")
    } catch (error) {
      this.setStatus(`PBW install failed: ${error.message}`)
    } finally {
      this.installing = false
      this.updateControlButtons()
    }
  }

  async loadCompanionPreferences() {
    if (!this.session) return
    if (!this.session?.backend_enabled) {
      this.setStatus("Launch the embedded emulator before opening companion preferences.")
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
          this.setStatus(data[data.length - 1] === 0 ? "PBW installed on embedded emulator" : "PBW install failed")
        }
        break
      case 0x08:
        this.appendLog(data[1] === 0xff ? "phone bridge connected to watch" : "phone bridge disconnected")
        if (data[1] === 0xff) this.enableAppLogs()
        break
      case 0x09:
        this.appendLog(data[1] === 0 ? "phone bridge authenticated" : "phone bridge authentication failed")
        if (data[1] === 0) this.enableAppLogs()
        break
      case 0x0a:
        this.handleConfigFrame(data)
        break
      case 0x0d:
        this.appendLog(data[1] === 0 ? "debug storage command sent" : "debug storage command failed")
        break
      default:
        this.appendLog(`phone frame ${data.byteLength} bytes`)
        break
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

  setBattery(percent, charging) {
    this.sendQemu(QEMU.battery, [Math.max(0, Math.min(100, percent || 0)), charging ? 1 : 0])
  }

  sendQemu(protocol, payload) {
    if (!this.phoneSocket || this.phoneSocket.readyState !== WebSocket.OPEN) return
    this.phoneSocket.send(new Uint8Array([0x0b, protocol, ...payload]))
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
    }
  }

  async installPbwViaPhoneBridge() {
    if (!this.session?.artifact_path) return
    if (!this.phoneSocket || this.phoneSocket.readyState !== WebSocket.OPEN) {
      this.appendLog("skipped phone bridge PBW install: phone websocket is not open")
      return
    }

    this.setStatus("Installing PBW on embedded emulator via phone bridge...")
    const response = await fetch(this.session.artifact_path)
    if (!response.ok) throw new Error(`Could not fetch PBW for phone bridge: ${response.statusText}`)

    const pbw = new Uint8Array(await response.arrayBuffer())
    const payload = new Uint8Array(1 + pbw.length)
    payload[0] = 0x04
    payload.set(pbw, 1)

    const result = this.waitForPypkjsInstall()
    this.phoneSocket.send(payload)
    this.appendLog(`sent PBW to phone bridge installer (${pbw.length} bytes)`)
    await result
    this.appendLog("phone bridge PBW install complete")
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

    this.flushPutBytesSummary()
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

  observeStorageLog(message) {
    const match = message.match(/(?:cmd|debug) storage_(read|write)(?:_string)? key=(\d+)(?: value=(.*?)(?: status=| rc=|$))?/)
    if (match) {
      const operation = match[1]
      const key = parseInt(match[2], 10)
      const stringLike = message.includes("storage_read_string") || message.includes("storage_write_string")
      const value = typeof match[3] === "string" ? match[3] : ""
      this.upsertStorageEntry({key, type: stringLike ? "string" : "int", value})
      if (operation === "read" && typeof match[3] !== "string") this.renderStorage()
      return
    }

    const deleted = message.match(/(?:cmd|debug) storage_delete key=(\d+)/)
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
    type.className = "rounded border border-zinc-300 px-2 py-1 text-xs"
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

  captureScreenshot() {
    if (!this.canvas) return
    const canvas = this.canvas.querySelector("canvas")
    if (!canvas) {
      this.setStatus("No embedded emulator canvas is available yet")
      return
    }
    const link = document.createElement("a")
    link.download = `embedded-emulator-${Date.now()}.png`
    link.href = canvas.toDataURL("image/png")
    link.click()
  }

  startPing() {
    this.stopPing()
    if (!this.session) return
    this.pingTimer = window.setInterval(async () => {
      try {
        const response = await postJSON(this.session.ping_path)
        if (response?.alive === false) this.endSession("Embedded emulator is no longer running")
      } catch (_error) {
        this.endSession("Embedded emulator is no longer reachable")
      }
    }, 5_000)
  }

  stopPing() {
    if (this.pingTimer) window.clearInterval(this.pingTimer)
    this.pingTimer = null
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
    if (!this.log) return
    if (options.flushTransfers !== false) this.flushPutBytesSummary()
    this.observeStorageLog(message)
    this.logLines.unshift(`${new Date().toLocaleTimeString()} ${message}`)
    this.logLines = this.logLines.slice(0, MAX_LOG_LINES)
    this.scheduleLogFlush()
  }

  scheduleLogFlush() {
    if (this.logFlushScheduled) return
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
  }

  endSession(message) {
    if (this.sessionEnded) return
    this.sessionEnded = true
    const oldPhoneSocket = this.phoneSocket
    this.session = null
    this.stopping = false
    this.installing = false
    this.pendingPypkjsInstall = null
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
    this.setButtonDisabled(this.launchButton, this.launching || this.stopping || hasSession)
    this.setButtonDisabled(this.installButton, this.launching || this.installing || this.stopping || !hasSession)
    this.setButtonDisabled(this.preferencesButton, this.launching || this.stopping || !hasSession)
    this.setButtonDisabled(this.stopButton, this.launching || this.stopping || !hasSession)
    this.setButtonDisabled(this.storageAddButton, this.launching || this.stopping || !hasSession)
    this.setButtonDisabled(this.storageResetButton, this.launching || this.stopping || !hasSession || this.storageEntries.size === 0)

    if (this.launchButton) this.launchButton.textContent = this.launching ? "Launching..." : "Launch"
    if (this.installButton) this.installButton.textContent = this.installing ? "Sending..." : "Send PBW"
    if (this.stopButton) this.stopButton.textContent = this.stopping ? "Stopping..." : "Stop"
  }

  setButtonDisabled(button, disabled) {
    if (!button) return
    button.disabled = disabled
    button.setAttribute("aria-disabled", disabled ? "true" : "false")
  }
}
