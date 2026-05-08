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
  }

  mount() {
    this.canvas = this.el.querySelector("[data-emulator-canvas]")
    this.status = this.el.querySelector("[data-emulator-status]")
    this.log = this.el.querySelector("[data-emulator-log]")
    this.configPanel = this.el.querySelector("[data-emulator-config-panel]")
    this.configFrame = this.el.querySelector("[data-emulator-config-frame]")
    this.configUrlLabel = this.el.querySelector("[data-emulator-config-url]")
    this.el.querySelector("[data-emulator-launch]")?.addEventListener("click", () => this.launch())
    this.el.querySelector("[data-emulator-stop]")?.addEventListener("click", () => this.stop())
    this.el.querySelector("[data-emulator-install]")?.addEventListener("click", () => this.install())
    this.el.querySelector("[data-emulator-screenshot]")?.addEventListener("click", () => this.captureScreenshot())
    this.el.querySelector("[data-emulator-config-open]")?.addEventListener("click", () => this.openConfigPopup())
    this.el.querySelector("[data-emulator-config-cancel]")?.addEventListener("click", () => this.cancelConfig())
    this.configFrame?.addEventListener("load", () => this.maybeHandleConfigReturn(this.configFrame.contentWindow))

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
  }

  destroy() {
    this.stopPing()
    this.stopConfigPopupPolling()
    if (this.rfb) this.rfb.disconnect()
    if (this.phoneSocket) this.phoneSocket.close()
  }

  async launch() {
    if (this.launching) return
    this.launching = true

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
    }
  }

  async stop() {
    if (!this.session) return
    await postJSON(this.session.kill_path)
    this.destroy()
    this.session = null
    this.setStatus("Embedded emulator stopped")
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
    if (this.installing) return
    this.installing = true

    try {
      if (!this.session) await this.launch()
      if (!this.session?.install_path) {
        this.setStatus("Embedded emulator install API is unavailable.")
        return
      }
      this.setStatus("Installing PBW on embedded emulator...")
      const response = await postJSON(this.session.install_path)
      const parts = response.result?.parts?.map(part => part.kind).join(", ")
      this.setStatus(parts ? `PBW installed on embedded emulator (${parts})` : "PBW installed on embedded emulator")
      this.appendLog("native PBW install complete")
    } catch (error) {
      this.setStatus(`PBW install failed: ${error.message}`)
    } finally {
      this.installing = false
    }
  }

  async handlePhoneMessage(event) {
    const data = new Uint8Array(await this.messageBytes(event.data))
    if (data.length === 0) return

    switch (data[0]) {
      case 0x00:
      case 0x01:
        break
      case 0x02:
        this.appendLog(new TextDecoder().decode(data.slice(1)))
        break
      case 0x05:
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

  async waitForPhoneBridgeSettle() {
    const minimumSettleMs = 5000
    const remaining = minimumSettleMs - (Date.now() - this.phoneOpenedAt)
    if (remaining <= 0) return

    this.setStatus("Waiting for phone bridge to settle before install...")
    await new Promise(resolve => window.setTimeout(resolve, remaining))
  }

  handleConfigFrame(data) {
    if (data[1] !== 0x01 || data.length < 6) return
    const length = new DataView(data.buffer, data.byteOffset + 2, 4).getUint32(0, false)
    const url = new TextDecoder().decode(data.slice(6, 6 + length))
    this.showConfigPage(url)
  }

  showConfigPage(url) {
    this.configUrl = this.withConfigReturnUrl(url)
    if (this.configUrlLabel) this.configUrlLabel.textContent = this.configUrl
    this.configPanel?.classList.remove("hidden")
    if (this.configFrame) this.configFrame.src = this.configUrl
    this.setStatus("Companion configuration requested")
  }

  withConfigReturnUrl(url) {
    const target = new URL(url, window.location.href)
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

  openConfigPopup() {
    if (!this.configUrl) return
    const popup = window.open(this.configUrl, "elm-pebble-config", "popup,width=420,height=720")
    if (!popup) {
      this.setStatus("Could not open configuration popup")
      return
    }

    this.stopConfigPopupPolling()
    this.configPopupTimer = window.setInterval(() => {
      if (popup.closed) {
        this.stopConfigPopupPolling()
        return
      }

      try {
        const location = popup.location
        if (location.origin === window.location.origin && location.pathname === CONFIG_RETURN_PATH) {
          this.completeConfig(location.search.replace(/^\?/, ""))
          popup.close()
        }
      } catch (_error) {
        // The popup remains cross-origin until the companion page redirects back.
      }
    }, 250)
  }

  completeConfig(query) {
    const bytes = new TextEncoder().encode(query)
    const out = new Uint8Array(6 + bytes.length)
    out[0] = 0x0a
    out[1] = 0x02
    new DataView(out.buffer).setUint32(2, bytes.length, false)
    out.set(bytes, 6)
    this.phoneSocket?.send(out)
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
    this.configPanel?.classList.add("hidden")
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
    if (this.status) this.status.textContent = message
    this.appendLog(message)
  }

  appendLog(message) {
    if (!this.log) return
    this.log.textContent = `${new Date().toLocaleTimeString()} ${message}\n${this.log.textContent || ""}`.slice(0, 8000)
  }

  clearLog() {
    if (this.log) this.log.textContent = ""
  }
}
