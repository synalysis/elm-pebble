import {applySimulatorSettingsToQemu, QEMU} from "./qemu_control.js"
import {postJSON} from "./emulator_http.js"

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

const DEBUG_SIMULATOR = {
  compassHeading: 0x454c4d10,
  dictationText: 0x454c4d11,
  weatherTemperatureC: 0x454c4d12,
  weatherConditionWire: 0x454c4d13
}

function qemuControlNames(protocols) {
  const map = {
    [QEMU.tap]: "tap",
    [QEMU.bluetooth]: "bluetooth",
    [QEMU.battery]: "battery",
    [QEMU.button]: "button",
    [QEMU.timeFormat]: "time_format",
    [QEMU.timelinePeek]: "timeline_peek",
    [QEMU.accel]: "accel",
    [QEMU.compass]: "compass"
  }
  return (protocols || []).map(p => map[p] || String(p)).join(", ")
}

export class EmulatorSimulatorDelivery {
  constructor(host) {
    this.host = host
  }

  reapplySimulatorSettingsToQemu(options = {}) {
    if (!this.host.emulatorSessionActive()) return

    if (!this.host.simulatorSettings) {
      this.host.refreshSimulatorSettingsFromDataset()
    }

    const settings = this.host.simulatorSettings
    if (!settings || typeof settings !== "object") return

    return this.applySimulatorSettings(settings, {
      source: options.source || "session_ready",
      quiet: options.quiet ?? true,
      syncCompanion: options.syncCompanion ?? false
    })
  }

  applyInitialSimulatorSettings() {
    const raw = this.host.el.dataset.emulatorSimulatorSettings
    if (!raw) return

    try {
      void this.applySimulatorSettings(JSON.parse(raw), {source: "dataset", syncCompanion: false})
      this.host.lastAppliedSimulatorSettingsJson = raw
    } catch (_error) {
      this.host.appendLog("Could not parse initial simulator settings from page")
    }
  }

  parseSimulatorCapabilities() {
    const raw = this.host.el.dataset.emulatorSimulatorCapabilities
    if (!raw) return new Set()

    try {
      const parsed = JSON.parse(raw)
      return new Set(Array.isArray(parsed) ? parsed : [])
    } catch (_error) {
      return new Set()
    }
  }

  simulatorCapabilities() {
    return this.host._simulatorCapabilities || (this.host._simulatorCapabilities = this.host.parseSimulatorCapabilities())
  }

  simulatorWeatherEnabled() {
    return this.host.simulatorCapabilities().has("weather")
  }

  refreshSimulatorCapabilities() {
    this.host._simulatorCapabilities = this.host.parseSimulatorCapabilities()
  }

  companionSimulatorEnabled() {
    return this.host.el.dataset.emulatorHasPhoneCompanion === "true"
  }

  emulatorSessionActive() {
    return !!this.host.session?.id
  }

  shouldSyncCompanionSimulator(options = {}) {
    return (
      this.host.companionSimulatorEnabled() &&
      this.host.emulatorSessionActive() &&
      options.syncCompanion !== false
    )
  }

  simulatorSettingsWeatherKey(settings = this.host.simulatorSettings) {
    return this.weatherDebugQueueKey(this.resolveWeatherSimulatorSettings(settings))
  }

  syncSimulatorSettingsFromDataset() {
    const raw = this.host.el.dataset.emulatorSimulatorSettings
    if (!raw || raw === this.host.lastAppliedSimulatorSettingsJson) return

    let incoming
    try {
      incoming = JSON.parse(raw)
    } catch (_error) {
      this.host.appendLog("Could not parse updated simulator settings from page")
      return
    }

    const incomingWeatherKey = this.host.simulatorSettingsWeatherKey(incoming)
    const currentWeatherKey = this.host.simulatorSettingsWeatherKey()

    // LiveView DOM patches can lag behind push_event; don't revert fresher settings.
    if (
      this.host.simulatorSettingsSource === "push_event" &&
      currentWeatherKey &&
      incomingWeatherKey !== currentWeatherKey
    ) {
      return
    }

    void this.applySimulatorSettings(incoming, {source: "dataset"})
    this.host.lastAppliedSimulatorSettingsJson = raw
  }

  refreshSimulatorSettingsFromDataset() {
    const raw = this.host.el.dataset.emulatorSimulatorSettings
    if (!raw) return

    try {
      this.host.simulatorSettings = JSON.parse(raw)
    } catch (_error) {
      this.host.appendLog("Could not parse simulator settings from page dataset")
    }
  }

  async applyQemuSimulatorSettings(settings, options = {}) {
    if (!this.host.session?.id) return null

    try {
      const response = await postJSON(
        `/api/emulator/${encodeURIComponent(this.host.session.id)}/simulator-settings`,
        {settings}
      )
      const result = response?.result
      if (!options.quiet && result?.applied) {
        const names = qemuControlNames(result.protocols)
        this.host.appendLog(
          `Applied ${result.applied} simulator setting(s) to QEMU${names ? ` (${names})` : ""}`
        )
      }
      this.host.lastQemuSettingsApply = {
        count: result?.applied ?? 0,
        source: options.source || "api",
        protocols: result?.protocols ?? []
      }
      return result
    } catch (error) {
      applySimulatorSettingsToQemu((protocol, payload) => this.host.sendQemu(protocol, payload), settings)
      if (!options.quiet) {
        this.host.appendLog(`simulator settings batch API failed, used per-control fallback: ${error.message}`)
      }
      return null
    }
  }

  async applySimulatorSettings(settings = {}, options = {}) {
    this.host.simulatorSettings = settings
    this.host.simulatorSettingsSource = options.source || "push_event"
    this.host.simulatorSettingsAppliedAt = Date.now()

    if (this.host.emulatorSessionActive()) {
      await this.applyQemuSimulatorSettings(settings, options)
    }

    if (this.host.shouldSyncCompanionSimulator(options)) {
      const quiet = options.quiet ?? options.source === "dataset"
      this.host.pushSimulatorSettingsToPhoneBridgeNow({quiet})
      if (this.host.simulatorWeatherEnabled()) {
        this.host.scheduleWeatherPush({quiet})
      }
    }

    this.host.lastAppliedSimulatorSettingsJson = JSON.stringify(this.host.simulatorSettingsPayload(settings))
  }

  simulatorSettingsPayload(settings = this.host.simulatorSettings) {
    if (!settings || typeof settings !== "object") {
      return this.host.simulatorWeatherEnabled() ? {weather: {...DEFAULT_SIMULATOR_WEATHER}} : {}
    }

    const payload = {...settings}
    const weather = this.host.resolveWeatherSimulatorSettings(settings)

    if (weather) {
      payload.weather = weather
    } else {
      delete payload.weather
      delete payload.weather_temperatureC
      delete payload.weather_condition
      delete payload.weather_humidityPercent
      delete payload.weather_pressureHpa
      delete payload.weather_windKph
    }

    return payload
  }

  pushSimulatorSettingsToPhoneBridgeNow(options = {}) {
    if (!this.host.companionSimulatorEnabled()) return false

    const payload = this.host.simulatorSettingsPayload()
    const sent = this.host.sendSimulatorSettingsToPhoneBridge(payload)
    if (sent && options.quiet === false && this.host.simulatorWeatherEnabled()) {
      const weather = this.host.resolveWeatherSimulatorSettings(payload)
      this.host.appendLog(
        `synced simulator weather via phone bridge: ${this.host.parseSimulatorTemperatureC(weather?.temperatureC) ?? "?"}°C ${weather?.condition || "clear"}`
      )
    }
    return sent
  }

  scheduleWeatherPush(options = {}) {
    if (!this.host.simulatorWeatherEnabled()) return
    if (!this.host.shouldSyncCompanionSimulator(options)) return
    this.host.resetWeatherDebugQueueIfStuck("new settings push")
    this.host.weatherDebugInFlight = false
    this.host.pendingWeatherRetry = null
    if (this.host.weatherDebugAckTimer != null) {
      window.clearTimeout(this.host.weatherDebugAckTimer)
      this.host.weatherDebugAckTimer = null
    }

    if (this.host.weatherPushTimer != null) {
      window.clearTimeout(this.host.weatherPushTimer)
    }
    if (this.host.weatherDebugFallbackTimer != null) {
      window.clearTimeout(this.host.weatherDebugFallbackTimer)
      this.host.weatherDebugFallbackTimer = null
    }

    this.host.weatherPushTimer = window.setTimeout(() => {
      this.host.weatherPushTimer = null
      const weather = this.host.resolveWeatherSimulatorSettings()
      const bridgeSent = this.host.pushSimulatorSettingsToPhoneBridgeNow()
      const injectTimerId = window.setTimeout(() => {
        this.host.weatherPushRetryTimers = this.host.weatherPushRetryTimers.filter(id => id !== injectTimerId)
        const injected = this.host.enqueueWeatherDebugPush(weather, {quiet: true, force: true})
        if (!injected && options.quiet === false) {
          this.host.appendLog(
            `skipped simulator weather inject: ${this.host.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
          )
        }
      }, 400)
      this.host.weatherPushRetryTimers.push(injectTimerId)
      this.host.scheduleWeatherDebugFallback(weather, {quiet: options.quiet !== false})
      if (options.quiet === false) {
        if (bridgeSent) {
          this.host.appendLog(
            `synced simulator weather via phone bridge: ${this.host.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
          )
        } else {
          this.host.appendLog("skipped simulator weather sync: phone bridge is not connected")
        }
      }
    }, 150)
  }

  scheduleWeatherDebugFallback(weather, options = {}) {
    if (this.host.weatherDebugFallbackTimer != null) {
      window.clearTimeout(this.host.weatherDebugFallbackTimer)
    }

    this.host.weatherDebugFallbackTimer = window.setTimeout(() => {
      this.host.weatherDebugFallbackTimer = null
      const sent = this.host.enqueueWeatherDebugPush(weather, {quiet: true, force: true})
      if (sent && options.quiet === false) {
        this.host.appendLog(
          `pushed simulator weather to watch: ${this.host.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
        )
      }
    }, 1500)
  }

  scheduleWeatherDebugAckTimeout() {
    if (this.host.weatherDebugAckTimer != null) {
      window.clearTimeout(this.host.weatherDebugAckTimer)
    }

    this.host.weatherDebugAckTimer = window.setTimeout(() => {
      this.host.weatherDebugAckTimer = null
      if (!this.host.weatherDebugInFlight) return
      this.host.weatherDebugInFlight = false
      this.host.drainWeatherDebugQueue()
    }, 2500)
  }

  weatherDebugQueueKey(weather) {
    return JSON.stringify({
      temperatureC: this.host.parseSimulatorTemperatureC(weather?.temperatureC),
      condition: weather?.condition || "clear"
    })
  }

  enqueueWeatherDebugPush(weather, options = {}) {
    if (!this.host.simulatorWeatherEnabled()) return false
    if (!this.host.session?.app_uuid) {
      if (options.quiet === false) {
        this.host.appendLog("skipped simulator weather: install a PBW on the emulator first")
      }
      return false
    }
    if (!this.host.phoneSocket || this.host.phoneSocket.readyState !== WebSocket.OPEN) {
      if (options.quiet === false) {
        this.host.appendLog("skipped simulator weather: phone bridge is not connected")
      }
      return false
    }

    const resolved = weather && typeof weather === "object" ? weather : DEFAULT_SIMULATOR_WEATHER
    const queueKey = this.host.weatherDebugQueueKey(resolved)
    if (!options.force && queueKey === this.host.lastSentWeatherJson) {
      return false
    }

    this.host.weatherDebugQueue = this.host.weatherDebugQueue.filter(item => item.queueKey !== queueKey)
    this.host.weatherDebugQueue.push({weather: resolved, options, queueKey})
    return this.host.drainWeatherDebugQueue()
  }

  drainWeatherDebugQueue() {
    if (this.host.weatherDebugInFlight || this.host.weatherDebugQueue.length === 0) {
      return false
    }

    const item = this.host.weatherDebugQueue.shift()
    this.host.weatherDebugInFlight = true
    this.host.weatherDebugInFlightAt = Date.now()
    this.host.pendingWeatherRetry = item.weather
    const sent = this.host.pushWeatherDebugAppMessage(item.weather, {quiet: true})
    if (!sent) {
      this.host.weatherDebugInFlight = false
      this.host.weatherDebugQueue.unshift(item)
      return false
    }

    this.host.scheduleWeatherDebugAckTimeout()
    return true
  }

  logWeatherTrace(bytes) {
    try {
      const trace = JSON.parse(new TextDecoder().decode(bytes))
      const temp = trace.temperatureC ?? trace.weather?.temperatureC ?? "?"
      const condition = trace.condition ?? trace.weather?.condition ?? "clear"
      const detail = trace.detail ? ` (${trace.detail})` : ""
      this.host.appendLog(`weather trace [${trace.stage}]: ${temp}°C ${condition}${detail}`)
    } catch (_error) {
      this.host.appendLog("weather trace: could not decode trace frame")
    }
  }

  resetWeatherDebugQueueIfStuck(reason) {
    if (!this.host.weatherDebugInFlight) return false
    const ageMs = Date.now() - this.host.weatherDebugInFlightAt
    if (ageMs < 2500) return false
    this.host.weatherDebugInFlight = false
    this.host.pendingWeatherRetry = null
    if (this.host.weatherDebugAckTimer != null) {
      window.clearTimeout(this.host.weatherDebugAckTimer)
      this.host.weatherDebugAckTimer = null
    }
    this.host.appendLog(`weather trace [queue_reset]: prior inject ack timed out (${reason}, ${ageMs}ms)`)
    return true
  }

  weatherConditionWireCode(condition) {
    const normalized = String(condition || "clear").toLowerCase().replace(/[^a-z0-9]+/g, "")
    return WEATHER_CONDITION_WIRE_CODES[normalized] || WEATHER_CONDITION_WIRE_CODES.clear
  }

  parseSimulatorTemperatureC(value) {
    if (value === null || value === undefined || value === "") return null
    const parsed = Number(value)
    return Number.isFinite(parsed) ? Math.round(parsed) : null
  }

  resolveWeatherSimulatorSettings(settings = this.host.simulatorSettings) {
    if (!settings || typeof settings !== "object") {
      return this.host.simulatorWeatherEnabled() ? DEFAULT_SIMULATOR_WEATHER : null
    }

    const nested = settings.weather
    if (nested && typeof nested === "object" && !Array.isArray(nested)) {
      return {
        temperatureC: nested.temperatureC ?? settings.weather_temperatureC ?? DEFAULT_SIMULATOR_WEATHER.temperatureC,
        condition: nested.condition ?? settings.weather_condition ?? DEFAULT_SIMULATOR_WEATHER.condition,
        humidityPercent: nested.humidityPercent ?? settings.weather_humidityPercent ?? DEFAULT_SIMULATOR_WEATHER.humidityPercent,
        pressureHpa: nested.pressureHpa ?? settings.weather_pressureHpa ?? DEFAULT_SIMULATOR_WEATHER.pressureHpa,
        windKph: nested.windKph ?? settings.weather_windKph ?? DEFAULT_SIMULATOR_WEATHER.windKph
      }
    }

    if (
      settings.weather_temperatureC != null ||
      settings.weather_condition != null ||
      settings.weather_humidityPercent != null ||
      settings.weather_pressureHpa != null ||
      settings.weather_windKph != null
    ) {
      return {
        temperatureC: settings.weather_temperatureC ?? DEFAULT_SIMULATOR_WEATHER.temperatureC,
        condition: settings.weather_condition || DEFAULT_SIMULATOR_WEATHER.condition,
        humidityPercent: settings.weather_humidityPercent ?? DEFAULT_SIMULATOR_WEATHER.humidityPercent,
        pressureHpa: settings.weather_pressureHpa ?? DEFAULT_SIMULATOR_WEATHER.pressureHpa,
        windKph: settings.weather_windKph ?? DEFAULT_SIMULATOR_WEATHER.windKph
      }
    }

    return this.host.simulatorWeatherEnabled() ? DEFAULT_SIMULATOR_WEATHER : null
  }

  scheduleWeatherSimulatorInject(reason) {
    if (!this.host.simulatorWeatherEnabled()) return
    this.host.weatherInjectTimers.forEach(timerId => window.clearTimeout(timerId))
    const timerId = window.setTimeout(() => {
      this.host.weatherInjectTimers = this.host.weatherInjectTimers.filter(id => id !== timerId)
      this.host.injectWeatherSimulatorSettings(reason)
    }, 2000)
    this.host.weatherInjectTimers = [timerId]
  }

  injectWeatherSimulatorSettings(reason) {
    if (!this.host.simulatorWeatherEnabled()) return
    const weather = this.host.resolveWeatherSimulatorSettings()
    const sent = this.host.pushWeatherDebugAppMessage(weather, {quiet: true})
    if (sent) {
      this.host.appendLog(
        `injected simulator weather (${reason}): ${this.host.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
      )
    }
  }

  pushWeatherDebugAppMessage(weather, options = {}) {
    if (!this.host.simulatorWeatherEnabled()) return false
    const resolved = weather && typeof weather === "object" ? weather : DEFAULT_SIMULATOR_WEATHER
    const temperatureC = this.host.parseSimulatorTemperatureC(resolved.temperatureC)
    const conditionWire = this.host.weatherConditionWireCode(resolved.condition)
    const entries = []

    if (temperatureC != null) {
      entries.push({key: DEBUG_SIMULATOR.weatherTemperatureC, type: "int", value: temperatureC})
    }
    entries.push({key: DEBUG_SIMULATOR.weatherConditionWire, type: "int", value: conditionWire})

    return this.host.sendDebugAppMessage(entries, options)
  }

  sendWeatherSimulatorSettings(weather, options = {}) {
    return this.host.enqueueWeatherDebugPush(weather, options)
  }

  sendSimulatorSettingsToPhoneBridge(settings = null) {
    const payload = settings ?? this.host.simulatorSettingsPayload()
    if (!payload) return false
    if (!this.host.phoneSocket || this.host.phoneSocket.readyState !== WebSocket.OPEN) return false

    const encoded = new TextEncoder().encode(JSON.stringify(payload))
    const out = new Uint8Array(1 + encoded.length)
    out[0] = 0x0e
    out.set(encoded, 1)
    this.host.phoneSocket.send(out)
    return true
  }
}
