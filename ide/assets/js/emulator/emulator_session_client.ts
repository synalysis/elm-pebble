import {postJSON} from "./emulator_http"
import {errMessage} from "../types/errors"
import {loadRFB} from "./emulator_vnc"
import type {EmbeddedEmulatorHostSurface} from "../types/emulator_host"
import type {EmulatorSessionInfo, PingResponse} from "../types/emulator"

type InstallResponse = {
  result?: {parts?: Array<{kind: string}>}
}

/**
 * HTTP session API for the embedded emulator (launch, stop, ping, native install).
 */
export class EmulatorSessionClient {
  host: EmbeddedEmulatorHostSurface

  constructor(host: EmbeddedEmulatorHostSurface) {
    this.host = host
  }

  async validatePersistedSession() {
    if (!this.host.session) return

    this.host.sessionAlive = false
    this.host.displayConnected = false
    this.host.phoneBridgeReady = false

    try {
      const response = await postJSON<PingResponse>(this.host.session.ping_path)
      if (response?.alive !== true) {
        this.host.endSession("Previous emulator session has ended")
        return
      }

      this.host.sessionAlive = true
    } catch (_error) {
      this.host.endSession("Previous emulator session is unreachable")
    }
  }

  async launch() {
    if (this.host.launching) return
    if (this.host.session) return

    const slug = this.host.el.dataset.projectSlug
    const platform = this.host.el.dataset.emulatorTarget
    if (!slug || !platform) {
      this.host.setStatus("Embedded emulator is missing project slug or watch model")
      return
    }

    this.host.launching = true
    this.host.notifyStateChanged()

    try {
      this.host.clearLog()
      this.host.hideConfigPage()
      this.host.sessionEnded = false
      this.host.appInstalled = false
      this.host.phoneCompanionCacheInstalled = false
      this.host.phoneCompanionInstalledAt = 0
      this.host.phoneBridgeReconnectAttempts = 0
      this.host.phoneBridgeReconnectWindowStartedAt = 0
      this.host.phoneBridgeLastReconnectedAt = 0
      this.host.setStatus("Launching embedded emulator...")
      void loadRFB().catch(() => {})
      this.host.session = await postJSON<EmulatorSessionInfo>("/api/emulator/launch", {slug, platform})
      this.host.sessionAlive = true
      this.host.displayConnected = false
      this.host.phoneBridgeReady = false

      if (!this.host.destroyed) {
        this.host.warnSessionScreenMismatch()
        this.host.logEmulatorPlatform()
        this.host.applyCanvasSize()
        const displayReady = await this.host.waitForDisplayReady()
        if (!displayReady && this.host.session && !this.host.destroyed) {
          this.host.appendLog("Embedded emulator VNC port was not ready before display connect timed out")
        }
        await this.host.connectDisplay()
        if (this.host.session && !this.host.destroyed) this.schedulePingAfterDisplayConnect()
      }
      if (this.host.session?.backend_enabled && this.host.displayConnected) {
        this.host.setStatus("Embedded emulator display connected")
      } else if (this.host.session?.backend_enabled) {
        this.host.setStatus("Embedded emulator session started; connecting display...")
      } else {
        this.host.setStatus("Embedded emulator backend disabled; launch API is in dry-run mode")
      }
      this.host.reapplySimulatorSettingsToQemu({source: "after_launch", quiet: true})
    } catch (error) {
      this.host.setStatus(`Embedded emulator failed: ${errMessage(error)}`)
    } finally {
      this.host.launching = false
      this.host.notifyStateChanged()
    }
  }

  async stop() {
    if (!this.host.session || this.host.stopping) return
    const session = this.host.session
    this.host.stopping = true
    this.host.notifyStateChanged()

    try {
      await postJSON(session.kill_path)
      this.host.endSession("Embedded emulator stopped")
    } catch (error) {
      this.host.setStatus(`Could not stop embedded emulator: ${errMessage(error)}`)
    } finally {
      this.host.stopping = false
      this.host.notifyStateChanged()
    }
  }

  async installPbwViaNativeInstaller(installSessionId = this.host.session?.id) {
    if (!this.host.session?.install_path) {
      this.host.setStatus("Embedded emulator install API is unavailable.")
      return
    }

    this.host.setStatus("Installing PBW on embedded emulator via fallback installer...")
    this.host.appendLog("native PBW install started (this can take a few minutes on large apps)")
    const response = await postJSON<InstallResponse>(this.host.session.install_path, {}, {timeoutMs: 300_000})
    if (this.host.session?.id !== installSessionId) return
    const parts = response.result?.parts?.map(part => part.kind).join(", ")
    this.host.appInstalled = true
    this.host.lastSentWeatherJson = null
    this.host.setStatus(parts ? `PBW installed on embedded emulator (${parts})` : "PBW installed on embedded emulator")
    this.host.appendLog("native PBW install complete")
    if (this.host.rfb) {
      this.host.scheduleVncViewportConfig(this.host.rfb, "after_install", 500)
      this.host.scheduleVncViewportConfig(this.host.rfb, "after_install_2s", 2000)
    }
  }

  schedulePingAfterDisplayConnect() {
    this.host.stopPingAfterDisplayTimer()
    if (!this.host.session || this.host.destroyed) return

    const start = () => {
      this.host.pingAfterDisplayTimer = null
      if (this.host.session && !this.host.destroyed) this.startPing()
    }

    if (this.host.displayConnected) {
      start()
      return
    }

    this.host.pingAfterDisplayTimer = window.setTimeout(start, 45_000)
  }

  startPing() {
    this.host.stopPing()
    if (!this.host.session || this.host.destroyed) return
    this.pingSession()
    this.host.pingTimer = window.setInterval(() => this.pingSession(), 5_000)
  }

  async pingSession() {
    const session = this.host.session
    if (!session || this.host.destroyed) return

    try {
      const response = await postJSON(session.ping_path)
      if (this.host.session?.id !== session.id || this.host.destroyed) return
      if (response?.alive === true) {
        this.host.sessionAlive = true
      } else if (!this.host.installing) {
        this.host.sessionAlive = false
        this.host.endSession("Embedded emulator is no longer running")
      }
    } catch (_error) {
      if (this.host.session?.id === session.id && !this.host.destroyed && !this.host.installing) {
        this.host.sessionAlive = false
        this.host.endSession("Embedded emulator is no longer reachable")
      }
    }
  }
}
