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
    this.suppressedPutBytesFrames = 0
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
    this.launchButton?.addEventListener("click", () => this.launch())
    this.stopButton?.addEventListener("click", () => this.stop())
    this.installButton?.addEventListener("click", () => this.install())
    this.preferencesButton?.addEventListener("click", () => this.loadCompanionPreferences())
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
    this.status = this.el.querySelector("[data-emulator-status]")
    this.log = this.el.querySelector("[data-emulator-log]")
    this.launchButton = this.el.querySelector("[data-emulator-launch]")
    this.installButton = this.el.querySelector("[data-emulator-install]")
    this.preferencesButton = this.el.querySelector("[data-emulator-preferences]")
    this.stopButton = this.el.querySelector("[data-emulator-stop]")

    if (this.status && this.currentStatus) {
      this.status.textContent = this.currentStatus
    }
    this.updateControlButtons()
  }

  destroy(removeListeners = true) {
    this.stopPing()
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
      this.destroy(false)
      this.session = null
      this.setStatus("Embedded emulator stopped")
    } catch (error) {
      this.setStatus(`Could not stop embedded emulator: ${error.message}`)
    } finally {
      this.stopping = false
      this.updateControlButtons()
    }
  }

  async connectVnc() {
    if (!this.session.backend_enabled || !this.canvas) return
    if (this.rfb) this.rfb.disconnect()
    const RFB = await loadRFB()
    this.rfb = new RFB(this.canvas, websocketURL(this.session.vnc_path), {shared: true})
    this.rfb.scaleViewport = true
    this.rfb.resizeSession = false
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
    })
    this.phoneSocket.addEventListener("close", () => this.appendLog("phone websocket closed"))
  }

  async install() {
    if (this.installing || !this.session) return
    this.installing = true
    this.updateControlButtons()

    try {
      if (!this.session?.install_path) {
        this.setStatus("Embedded emulator install API is unavailable.")
        return
      }
      await this.loadPbwIntoPhoneBridge()
      this.setStatus("Installing PBW on embedded emulator...")
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
        this.finishPypkjsInstall(data[data.length - 1] === 0)
        this.setStatus(data[data.length - 1] === 0 ? "PBW installed on embedded emulator" : "PBW install failed")
        break
      case 0x08:
        this.appendLog(data[1] === 0xff ? "phone bridge connected to watch" : "phone bridge disconnected")
        break
      case 0x09:
        this.appendLog(data[1] === 0 ? "phone bridge authenticated" : "phone bridge authentication failed")
        break
      case 0x0a:
        this.handleConfigFrame(data)
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

  async loadPbwIntoPhoneBridge() {
    if (!this.session?.artifact_path) return
    if (!this.phoneSocket || this.phoneSocket.readyState !== WebSocket.OPEN) {
      this.appendLog("skipped companion JS load: phone bridge websocket is not open")
      return
    }

    this.setStatus("Loading companion JS into phone bridge...")
    const response = await fetch(this.session.artifact_path)
    if (!response.ok) throw new Error(`Could not fetch PBW for phone bridge: ${response.statusText}`)

    const pbw = new Uint8Array(await response.arrayBuffer())
    const payload = new Uint8Array(1 + pbw.length)
    payload[0] = 0x04
    payload.set(pbw, 1)

    const result = this.waitForPypkjsInstall()
    this.phoneSocket.send(payload)
    this.appendLog(`sent PBW to phone bridge for companion JS (${pbw.length} bytes)`)
    await result
    this.appendLog("phone bridge loaded PBW companion JS")
  }

  waitForPypkjsInstall() {
    if (this.pendingPypkjsInstall) return this.pendingPypkjsInstall.promise

    let pending
    const promise = new Promise((resolve, reject) => {
      const timeoutId = window.setTimeout(() => {
        this.pendingPypkjsInstall = null
        reject(new Error("Timed out waiting for phone bridge PBW install"))
      }, 30000)
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

    return `${direction} ${endpointName} endpoint=0x${endpoint.toString(16).padStart(4, "0")} payload=${length} bytes ${this.hexPreview(payload)}`
  }

  endpointName(endpoint) {
    switch (endpoint) {
      case 0x0030:
        return "AppMessage"
      case 0x0034:
        return "App run state"
      case 0x1771:
        return "App fetch"
      case 0x1a7a:
        return "App log"
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
    this.pingTimer = window.setInterval(() => postJSON(this.session.ping_path).catch(() => this.stopPing()), 60_000)
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
    this.logLines.unshift(`${new Date().toLocaleTimeString()} ${message}`)
    this.logLines = this.logLines.slice(0, MAX_LOG_LINES)
    this.log.textContent = this.logLines.join("\n").slice(0, MAX_LOG_CHARS)
  }

  clearLog() {
    this.logLines = []
    this.suppressedPutBytesFrames = 0
    if (this.log) this.log.textContent = ""
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
