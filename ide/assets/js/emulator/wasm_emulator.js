const MAX_LOG_LINES = 200
const QEMU = {
  tap: 2,
  bluetooth: 3,
  battery: 5,
  timeFormat: 9,
  timelinePeek: 10
}

const csrfToken = () => document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""

async function getJSON(url) {
  const response = await fetch(url)
  const data = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(data.error || response.statusText)
  return data
}

async function postJSON(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: {"content-type": "application/json", "x-csrf-token": csrfToken()},
    body: JSON.stringify(body)
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(data.error || response.statusText)
  return data
}

export class WasmEmulatorHost {
  constructor(hook) {
    this.hook = hook
    this.el = hook.el
    this.logLines = []
    this.frameLoaded = false
    this.runtimeReady = false
    this.launching = false
    this.installing = false
    this.screenshotPending = false
    this.wasmPlatform = null
    this.watchPlatform = null
    this.firmware = {}
    this.selectedFirmware = "sdk"
    this.assetStatus = null
    this.currentStatus = null
    this.currentAssets = null
    this.progressState = null
    this.storageEntries = new Map()
    this.handleMessage = event => this.onMessage(event)
  }

  mount() {
    this.frame = this.el.querySelector("[data-wasm-frame]")
    this.status = this.el.querySelector("[data-wasm-status]")
    this.assets = this.el.querySelector("[data-wasm-assets]")
    this.log = this.el.querySelector("[data-wasm-log]")
    this.launchButton = this.el.querySelector("[data-wasm-launch]")
    this.firmwareSelect = this.el.querySelector("[data-wasm-firmware]")
    this.installButton = this.el.querySelector("[data-wasm-install]")
    this.screenshotButton = this.el.querySelector("[data-wasm-screenshot]")
    this.progress = this.el.querySelector("[data-wasm-progress]")
    this.progressLabel = this.el.querySelector("[data-wasm-progress-label]")
    this.progressPercent = this.el.querySelector("[data-wasm-progress-percent]")
    this.progressBar = this.el.querySelector("[data-wasm-progress-bar]")
    this.storageRows = this.el.querySelector("[data-wasm-storage-rows]")
    this.tapButton = this.el.querySelector("[data-wasm-tap]")

    this.launchButton?.addEventListener("click", () => this.toggleLaunch())
    this.firmwareSelect?.addEventListener("change", () => {
      this.selectedFirmware = this.firmwareSelect.value || "sdk"
      this.watchPlatform = null
      this.wasmPlatform = this.platformForFirmware(this.selectedFirmware)
      this.renderAssetsStatus()
      this.updateButtons()
    })
    this.installButton?.addEventListener("click", () => this.installPbw())
    this.screenshotButton?.addEventListener("click", () => this.requestScreenshot())
    this.el.querySelector("[data-wasm-battery]")?.addEventListener("input", event => {
      this.setBattery(parseInt(event.target.value || "80", 10), this.el.querySelector("[data-wasm-charging]")?.checked)
    })
    this.el.querySelector("[data-wasm-charging]")?.addEventListener("change", event => {
      const battery = parseInt(this.el.querySelector("[data-wasm-battery]")?.value || "80", 10)
      this.setBattery(battery, event.target.checked)
    })
    this.el.querySelector("[data-wasm-bluetooth]")?.addEventListener("change", event => this.sendQemu(QEMU.bluetooth, [event.target.checked ? 1 : 0]))
    this.el.querySelector("[data-wasm-24h]")?.addEventListener("change", event => this.sendQemu(QEMU.timeFormat, [event.target.checked ? 1 : 0]))
    this.el.querySelector("[data-wasm-peek]")?.addEventListener("change", event => this.sendQemu(QEMU.timelinePeek, [event.target.checked ? 1 : 0]))
    this.tapButton?.addEventListener("click", () => this.sendQemu(QEMU.tap, [0, 1]))

    this.el.querySelectorAll("[data-wasm-button]").forEach(button => {
      const name = button.dataset.wasmButton
      button.addEventListener("pointerdown", event => {
        event.preventDefault()
        this.sendButton(name, true)
      })
      button.addEventListener("pointerup", () => this.sendButton(name, false))
      button.addEventListener("pointerleave", () => this.sendButton(name, false))
    })

    window.addEventListener("message", this.handleMessage)
    if (!this.ensureCrossOriginIsolation()) return
    this.checkAssets()
    this.updateButtons()
  }

  updated() {
    this.mountRefs()
    this.restorePanelState()
    this.renderAssetsStatus()
    this.renderStorage()
    this.updateButtons()
  }

  mountRefs() {
    this.frame = this.el.querySelector("[data-wasm-frame]")
    this.status = this.el.querySelector("[data-wasm-status]")
    this.assets = this.el.querySelector("[data-wasm-assets]")
    this.log = this.el.querySelector("[data-wasm-log]")
    this.launchButton = this.el.querySelector("[data-wasm-launch]")
    this.firmwareSelect = this.el.querySelector("[data-wasm-firmware]")
    this.installButton = this.el.querySelector("[data-wasm-install]")
    this.screenshotButton = this.el.querySelector("[data-wasm-screenshot]")
    this.progress = this.el.querySelector("[data-wasm-progress]")
    this.progressLabel = this.el.querySelector("[data-wasm-progress-label]")
    this.progressPercent = this.el.querySelector("[data-wasm-progress-percent]")
    this.progressBar = this.el.querySelector("[data-wasm-progress-bar]")
    this.storageRows = this.el.querySelector("[data-wasm-storage-rows]")
    this.tapButton = this.el.querySelector("[data-wasm-tap]")
  }

  destroy() {
    window.removeEventListener("message", this.handleMessage)
  }

  ensureCrossOriginIsolation() {
    const reloadKey = `elm-pebble-wasm-isolation-reload:${window.location.pathname}`
    if (window.crossOriginIsolated) {
      sessionStorage.removeItem(reloadKey)
      return true
    }

    if (!sessionStorage.getItem(reloadKey)) {
      sessionStorage.setItem(reloadKey, "1")
      this.setStatus("Reloading page to enable WASM cross-origin isolation...")
      window.location.reload()
    } else {
      this.setStatus("WASM emulator requires a cross-origin isolated page. Refresh this page and try again.")
    }

    return false
  }

  async checkAssets() {
    try {
      const status = await getJSON("/api/wasm-emulator/status")
      const assetsAvailable = status.available === true || status["available?"] === true
      const installBridgeAvailable = status.install_bridge?.available === true || status.install_bridge?.["available?"] === true
      this.assetStatus = status
      this.firmware = status.firmware || {}
      this.wasmPlatform = this.platformForFirmware(this.selectedFirmware)

      this.assetsAvailable = assetsAvailable
      this.installBridgeAvailable = installBridgeAvailable
      this.renderAssetsStatus()
    } catch (error) {
      this.setAssets(`Could not check WASM assets: ${error.message}`)
      this.assetsAvailable = false
      this.installBridgeAvailable = false
    }
    this.updateButtons()
  }

  renderAssetsStatus() {
    const status = this.assetStatus
    if (!status) return

    if (this.assetsAvailable) {
      const bridge = this.installBridgeAvailable ? "install bridge ready" : `install bridge missing: ${status.install_bridge?.required_api || "patched Pebble control bridge"}`
      const firmware = this.firmwareSummary()
      this.setAssets(`Assets ready at ${status.root}; ${firmware}; ${bridge}`)
    } else {
      this.setAssets(this.missingAssetMessage(status))
    }
  }

  installPlatform() {
    return this.watchPlatform || this.wasmPlatform || this.el.dataset.emulatorTarget || "emery"
  }

  selectedTarget() {
    return this.el.dataset.emulatorTarget || "emery"
  }

  platformForFirmware(name) {
    if (name === "sdk") {
      const target = this.selectedTarget()
      if (this.firmware?.sdk?.platforms?.[target]) return target
      return this.firmware?.sdk?.platform || this.firmware?.sdk?.legacy?.platform || null
    }

    return this.firmware?.[name]?.platform || (name === "full" ? "emery" : null)
  }

  firmwareAssetPath(name) {
    if (name === "sdk") {
      const target = this.selectedTarget()
      if (this.firmware?.sdk?.platforms?.[target]) return `sdk/${target}`
      if (this.firmware?.sdk?.platform || this.firmware?.sdk?.legacy) return "sdk"
      return null
    }

    return name
  }

  launchReady() {
    return this.assetsAvailable && !!this.firmwareAssetPath(this.firmwareSelect?.value || this.selectedFirmware || "sdk")
  }

  firmwareSummary() {
    const target = this.selectedTarget()
    const sdkPlatforms = Object.keys(this.firmware?.sdk?.platforms || {})
    const legacyPlatform = this.firmware?.sdk?.platform || this.firmware?.sdk?.legacy?.platform

    const sdk = (() => {
      if (sdkPlatforms.length > 0) {
        return this.firmware?.sdk?.platforms?.[target] ? `SDK ${target}` : `SDK missing for ${target} (available: ${sdkPlatforms.join(", ")})`
      }

      if (legacyPlatform) {
        return legacyPlatform === target ? `SDK ${legacyPlatform}` : `SDK ${legacyPlatform} legacy fallback for selected ${target}`
      }

      return `SDK missing for ${target}`
    })()

    const full = this.firmware?.full?.platform ? `full ${this.firmware.full.platform}` : "full unavailable"
    return `firmware ${sdk}; ${full}`
  }

  toggleLaunch() {
    if (this.frameLoaded || this.runtimeReady) {
      this.stop()
    } else {
      this.launch()
    }
  }

  launch() {
    if (this.launching) return
    if (!this.launchReady()) {
      this.setStatus("WASM SDK firmware for the selected watch model is not available.")
      return
    }
    this.launching = true
    this.frameLoaded = false
    this.runtimeReady = false
    this.setStatus("Loading WASM emulator frame...")
    this.resetFrame()
    this.frame.addEventListener("load", () => {
      this.frameLoaded = true
      this.selectedFirmware = this.firmwareSelect?.value || "sdk"
      this.watchPlatform = null
      this.wasmPlatform = this.platformForFirmware(this.selectedFirmware)
      this.postToFrame({type: "launch", firmware: this.firmwareAssetPath(this.selectedFirmware)})
      this.launching = false
      this.updateButtons()
    }, {once: true})
    this.frame.src = "/wasm-emulator"
    this.updateButtons()
  }

  stop() {
    this.resetFrame()
    this.frameLoaded = false
    this.runtimeReady = false
    this.watchPlatform = null
    this.installing = false
    this.screenshotPending = false
    this.hideProgress()
    this.setStatus("WASM emulator stopped")
    this.updateButtons()
  }

  resetFrame() {
    if (!this.frame) return

    const replacement = this.frame.cloneNode(false)
    replacement.removeAttribute("src")
    this.frame.replaceWith(replacement)
    this.frame = replacement
  }

  async installPbw() {
    if (this.installing) return
    if (!this.installReady()) {
      this.setStatus("Wait until the WASM emulator runtime is ready before installing a PBW.")
      return
    }
    this.installing = true
    this.setProgress("Building PBW", 5)
    this.setStatus("Building PBW for WASM install...")
    this.updateButtons()

    try {
      const platform = this.installPlatform()
      const firmware = this.selectedFirmware || "sdk"
      const url = `/api/wasm-emulator/projects/${encodeURIComponent(this.el.dataset.projectSlug)}/install-plan?platform=${encodeURIComponent(platform)}&firmware=${encodeURIComponent(firmware)}`
      const plan = await getJSON(url)
      const totalBytes = (plan.parts || []).reduce((sum, part) => sum + (part.size || 0), 0)
      this.setProgress("Sending install plan", 10)
      this.setStatus(`Installing ${plan.variant || platform} PBW in WASM emulator (${Math.round(totalBytes / 1024)}KB)...`)
      this.postToFrame({type: "installPbw", plan})
    } catch (error) {
      this.installing = false
      this.hideProgress()
      this.setStatus(`Could not install PBW: ${error.message}`)
      this.updateButtons()
    }
  }

  requestScreenshot() {
    if (!this.runtimeReady || this.screenshotPending) return
    this.screenshotPending = true
    this.postToFrame({type: "screenshot"})
    this.setStatus("Capturing WASM emulator screenshot...")
    this.updateButtons()
  }

  async saveScreenshot(image) {
    try {
      const result = await postJSON(`/api/wasm-emulator/projects/${encodeURIComponent(this.el.dataset.projectSlug)}/screenshot`, {
        platform: this.installPlatform(),
        image
      })
      if (result.screenshot) {
        this.hook.pushEvent("wasm-screenshot-saved", {screenshot: result.screenshot})
      }
      this.setStatus("Saved WASM emulator screenshot")
    } catch (error) {
      this.setStatus(`Could not save screenshot: ${error.message}`)
    } finally {
      this.screenshotPending = false
      this.updateButtons()
    }
  }

  sendButton(name, pressed) {
    if (!this.runtimeReady) return
    this.postToFrame({type: "button", name, pressed})
  }

  setBattery(percent, charging) {
    this.sendQemu(QEMU.battery, [Math.max(0, Math.min(100, percent || 0)), charging ? 1 : 0])
  }

  sendQemu(protocol, payload) {
    if (!this.runtimeReady) return
    this.postToFrame({type: "qemuControl", protocol, payload})
  }

  postToFrame(message, transfer = []) {
    this.frame?.contentWindow?.postMessage(message, window.location.origin, transfer)
  }

  onMessage(event) {
    if (event.origin !== window.location.origin) return
    const message = event.data || {}
    if (message.source !== "elm-pebble-wasm-emulator") return

    if (message.type === "loaded") {
      this.frameLoaded = true
      this.setStatus(message.isolated ? "WASM emulator frame loaded" : "WASM emulator frame loaded without cross-origin isolation")
    } else if (message.type === "ready") {
      this.runtimeReady = true
      this.setStatus("WASM emulator runtime ready")
    } else if (message.type === "status") {
      this.setStatus(message.message)
    } else if (message.type === "log") {
      this.appendLog(message.message)
    } else if (message.type === "watch-info") {
      if (message.platform && message.platform !== "unknown") {
        this.watchPlatform = message.platform
        this.setStatus(`WASM watch reports ${message.platform} (${message.version || "unknown firmware"})`)
      }
    } else if (message.type === "screenshot") {
      this.saveScreenshot(message.image)
    } else if (message.type === "install-ok") {
      this.installing = false
      this.setProgress("Install complete", 100)
      this.setStatus("PBW installed in WASM emulator")
    } else if (message.type === "install-error") {
      this.installing = false
      this.hideProgress()
      this.setStatus(`WASM install failed: ${message.error}`)
    } else if (message.type === "progress") {
      this.setProgress(message.label || "Installing PBW", message.percent || 0)
    }
    this.updateButtons()
  }

  setStatus(message) {
    this.currentStatus = message
    if (this.status) this.status.textContent = message
    this.appendLog(message)
  }

  setAssets(message) {
    this.currentAssets = message
    if (this.assets) this.assets.textContent = message
  }

  setProgress(label, percent) {
    const bounded = Math.max(0, Math.min(100, Math.round(percent)))
    this.progressState = {label, percent: bounded}
    if (this.progress) this.progress.classList.remove("hidden")
    if (this.progressLabel) this.progressLabel.textContent = label
    if (this.progressPercent) this.progressPercent.textContent = `${bounded}%`
    if (this.progressBar) this.progressBar.style.width = `${bounded}%`
  }

  hideProgress() {
    this.progressState = null
    if (this.progress) this.progress.classList.add("hidden")
    if (this.progressBar) this.progressBar.style.width = "0%"
  }

  restorePanelState() {
    if (this.currentStatus && this.status) this.status.textContent = this.currentStatus
    if (this.currentAssets && this.assets) this.assets.textContent = this.currentAssets
    if (this.log) this.log.textContent = this.logLines.join("\n")

    if (this.progressState) {
      if (this.progress) this.progress.classList.remove("hidden")
      if (this.progressLabel) this.progressLabel.textContent = this.progressState.label
      if (this.progressPercent) this.progressPercent.textContent = `${this.progressState.percent}%`
      if (this.progressBar) this.progressBar.style.width = `${this.progressState.percent}%`
    } else {
      if (this.progress) this.progress.classList.add("hidden")
      if (this.progressBar) this.progressBar.style.width = "0%"
    }
  }

  missingAssetMessage(status) {
    const parts = []
    if (status.runtime_missing?.length) {
      parts.push(`QEMU runtime missing: ${status.runtime_missing.join(", ")} -> ${status.setup?.runtime_target || status.root}`)
    }
    if (status.firmware_missing?.length) {
      parts.push(`SDK firmware missing: ${status.firmware_missing.map(path => path.replace(/^firmware\/sdk\//, "")).join(", ")} -> ${status.setup?.sdk_firmware_target || status.root}`)
    }
    if (parts.length === 0) parts.push("WASM assets are present, but the install bridge is not ready.")
    parts.push(`Upstream: ${status.setup?.upstream_url || "https://github.com/ericmigi/pebble-qemu-wasm"}`)
    return parts.join(" | ")
  }

  appendLog(message) {
    if (!message) return
    this.observeStorageLog(message)
    this.logLines.unshift(`${new Date().toLocaleTimeString()} ${message}`)
    this.logLines = this.logLines.slice(0, MAX_LOG_LINES)
    if (this.log) this.log.textContent = this.logLines.join("\n")
  }

  observeStorageLog(message) {
    const match = message.match(/(?:cmd|debug) storage_(read|write)(?:_string)? key=(\d+)(?: value=(.*?)(?: status=| rc=|$))?/)
    if (match) {
      const operation = match[1]
      const key = parseInt(match[2], 10)
      const stringLike = message.includes("storage_read_string") || message.includes("storage_write_string")
      const value = typeof match[3] === "string" ? match[3] : ""
      this.storageEntries.set(String(key), {
        key,
        type: stringLike ? "string" : "int",
        value,
        source: operation === "read" ? "read log" : "write log"
      })
      this.renderStorage()
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
      this.storageRows.innerHTML = `<tr data-wasm-storage-empty><td colspan="4" class="py-3 text-zinc-500">No storage keys observed yet. Launch the app and install the PBW to collect storage logs.</td></tr>`
      return
    }

    this.storageRows.replaceChildren(...entries.map(entry => {
      const row = document.createElement("tr")
      row.className = "border-b border-zinc-100 last:border-0"
      row.innerHTML = `
        <td class="py-2 pr-2 font-mono text-zinc-800"></td>
        <td class="py-2 pr-2"></td>
        <td class="py-2 pr-2"></td>
        <td class="py-2 text-right text-zinc-500"></td>
      `
      row.children[0].textContent = String(entry.key)
      row.children[1].textContent = entry.type
      row.children[2].textContent = entry.value
      row.children[3].textContent = entry.source || "app log"
      return row
    }))
  }

  updateButtons() {
    const running = this.frameLoaded || this.runtimeReady
    if (this.launchButton) this.launchButton.textContent = running ? "Stop" : "Launch"
    this.setDisabled(this.launchButton, (!this.launchReady() && !running) || this.launching)
    this.setDisabled(this.installButton, this.installing || !this.installReady())
    this.setDisabled(this.screenshotButton, !this.runtimeReady || this.screenshotPending)
    this.setDisabled(this.tapButton, !this.runtimeReady)
  }

  setDisabled(button, disabled) {
    if (button) button.disabled = disabled
  }

  installReady() {
    return this.runtimeReady && this.installBridgeAvailable && !this.installing
  }
}
