import {applySimulatorSettingsToQemu, QEMU} from "./qemu_control"
import {postJSON} from "./emulator_http"
import type {ApplySettingsResult, SimulatorSettings} from "../types/emulator"
import type {
  QemuSettingsApplyRecord,
  SimulatorSettingsOptions,
  SimulatorSettingsPayload,
  WeatherDebugOptions,
  WeatherSimulatorSettings,
  QuietOptions
} from "../types/emulator_options"
import type {SimulatorDeliveryHost} from "../types/simulator_host"
import {errMessage} from "../types/errors"

const DEFAULT_SIMULATOR_WEATHER: WeatherSimulatorSettings = {
  temperatureC: 21,
  condition: "clear"
}

const WEATHER_CONDITION_WIRE_CODES: Record<string, number> = {
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
} as const

const QEMU_PROTOCOL_NAMES: Record<number, string> = {
  [QEMU.tap]: "tap",
  [QEMU.bluetooth]: "bluetooth",
  [QEMU.battery]: "battery",
  [QEMU.button]: "button",
  [QEMU.timeFormat]: "time_format",
  [QEMU.timelinePeek]: "timeline_peek",
  [QEMU.accel]: "accel",
  [QEMU.compass]: "compass"
}

function qemuControlNames(protocols: number[] | undefined): string {
  return (protocols || []).map(p => QEMU_PROTOCOL_NAMES[p] || String(p)).join(", ")
}

type SimulatorSettingsApiBody = {
  result?: ApplySettingsResult
}

export class EmulatorSimulatorDelivery {
  host: SimulatorDeliveryHost

  constructor(host: SimulatorDeliveryHost) {
    this.host = host
  }

  reapplySimulatorSettingsToQemu(options: SimulatorSettingsOptions = {}) {
    if (!this.emulatorSessionActive()) return

    if (!this.host.simulatorSettings) {
      this.refreshSimulatorSettingsFromDataset()
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
      void this.applySimulatorSettings(JSON.parse(raw) as SimulatorSettings, {
        source: "dataset",
        syncCompanion: false
      })
      this.host.lastAppliedSimulatorSettingsJson = raw
    } catch {
      this.host.appendLog("Could not parse initial simulator settings from page")
    }
  }

  parseSimulatorCapabilities(): Set<string> {
    const raw = this.host.el.dataset.emulatorSimulatorCapabilities
    if (!raw) return new Set()

    try {
      const parsed: unknown = JSON.parse(raw)
      return new Set(Array.isArray(parsed) ? (parsed as string[]) : [])
    } catch {
      return new Set()
    }
  }

  simulatorCapabilities(): Set<string> {
    return (
      this.host._simulatorCapabilities ||
      (this.host._simulatorCapabilities = this.parseSimulatorCapabilities())
    )
  }

  simulatorWeatherEnabled(): boolean {
    return this.simulatorCapabilities().has("weather")
  }

  refreshSimulatorCapabilities(): void {
    this.host._simulatorCapabilities = this.parseSimulatorCapabilities()
  }

  companionSimulatorEnabled(): boolean {
    return this.host.el.dataset.emulatorHasPhoneCompanion === "true"
  }

  emulatorSessionActive(): boolean {
    return !!this.host.session?.id
  }

  shouldSyncCompanionSimulator(options: SimulatorSettingsOptions = {}): boolean {
    return (
      this.companionSimulatorEnabled() &&
      this.emulatorSessionActive() &&
      options.syncCompanion !== false
    )
  }

  simulatorSettingsWeatherKey(settings: SimulatorSettings | null = this.host.simulatorSettings): string {
    return this.weatherDebugQueueKey(this.resolveWeatherSimulatorSettings(settings))
  }

  syncSimulatorSettingsFromDataset(): void {
    const raw = this.host.el.dataset.emulatorSimulatorSettings
    if (!raw || raw === this.host.lastAppliedSimulatorSettingsJson) return

    let incoming: SimulatorSettings
    try {
      incoming = JSON.parse(raw) as SimulatorSettings
    } catch {
      this.host.appendLog("Could not parse updated simulator settings from page")
      return
    }

    const incomingWeatherKey = this.simulatorSettingsWeatherKey(incoming)
    const currentWeatherKey = this.simulatorSettingsWeatherKey()

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

  refreshSimulatorSettingsFromDataset(): void {
    const raw = this.host.el.dataset.emulatorSimulatorSettings
    if (!raw) return

    try {
      this.host.simulatorSettings = JSON.parse(raw) as SimulatorSettings
    } catch {
      this.host.appendLog("Could not parse simulator settings from page dataset")
    }
  }

  async applyQemuSimulatorSettings(
    settings: SimulatorSettings,
    options: SimulatorSettingsOptions = {}
  ): Promise<ApplySettingsResult | null> {
    const sessionId = this.host.session?.id
    if (!sessionId) return null

    try {
      const response = await postJSON<SimulatorSettingsApiBody>(
        `/api/emulator/${encodeURIComponent(sessionId)}/simulator-settings`,
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
      return result ?? null
    } catch (error) {
      applySimulatorSettingsToQemu(
        (protocol, payload) => this.host.sendQemu(protocol, payload),
        settings
      )
      if (!options.quiet) {
        this.host.appendLog(
          `simulator settings batch API failed, used per-control fallback: ${errMessage(error)}`
        )
      }
      return null
    }
  }

  async applySimulatorSettings(
    settings: SimulatorSettings = {},
    options: SimulatorSettingsOptions = {}
  ): Promise<void> {
    this.host.simulatorSettings = settings
    this.host.simulatorSettingsSource = options.source || "push_event"
    this.host.simulatorSettingsAppliedAt = Date.now()

    if (this.emulatorSessionActive()) {
      await this.applyQemuSimulatorSettings(settings, options)
    }

    if (this.shouldSyncCompanionSimulator(options)) {
      const quiet = options.quiet ?? options.source === "dataset"
      this.pushSimulatorSettingsToPhoneBridgeNow({quiet})
      if (this.simulatorWeatherEnabled()) {
        this.scheduleWeatherPush({quiet})
      }
    }

    this.host.lastAppliedSimulatorSettingsJson = JSON.stringify(
      this.simulatorSettingsPayload(settings)
    )
  }

  simulatorSettingsPayload(
    settings: SimulatorSettings | null = this.host.simulatorSettings
  ): SimulatorSettingsPayload {
    if (!settings || typeof settings !== "object") {
      return this.simulatorWeatherEnabled() ? {weather: {...DEFAULT_SIMULATOR_WEATHER}} : {}
    }

    const payload: SimulatorSettingsPayload = {...settings}
    const weather = this.resolveWeatherSimulatorSettings(settings)

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

  pushSimulatorSettingsToPhoneBridgeNow(options: QuietOptions = {}): boolean {
    if (!this.companionSimulatorEnabled()) return false

    const payload = this.simulatorSettingsPayload()
    const sent = this.sendSimulatorSettingsToPhoneBridge(payload)
    if (sent && options.quiet === false && this.simulatorWeatherEnabled()) {
      const weather = this.resolveWeatherSimulatorSettings(payload)
      this.host.appendLog(
        `synced simulator weather via phone bridge: ${this.parseSimulatorTemperatureC(weather?.temperatureC) ?? "?"}°C ${weather?.condition || "clear"}`
      )
    }
    return sent
  }

  scheduleWeatherPush(options: SimulatorSettingsOptions = {}): void {
    if (!this.simulatorWeatherEnabled()) return
    if (!this.shouldSyncCompanionSimulator(options)) return
    this.resetWeatherDebugQueueIfStuck("new settings push")
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
      const weather = this.resolveWeatherSimulatorSettings() ?? DEFAULT_SIMULATOR_WEATHER
      const bridgeSent = this.pushSimulatorSettingsToPhoneBridgeNow()
      const injectTimerId = window.setTimeout(() => {
        this.host.weatherPushRetryTimers = this.host.weatherPushRetryTimers.filter(
          id => id !== injectTimerId
        )
        const injected = this.enqueueWeatherDebugPush(weather, {quiet: true, force: true})
        if (!injected && options.quiet === false) {
          this.host.appendLog(
            `skipped simulator weather inject: ${this.parseSimulatorTemperatureC(weather?.temperatureC) ?? "?"}°C ${weather?.condition || "clear"}`
          )
        }
      }, 400)
      this.host.weatherPushRetryTimers.push(injectTimerId)
      this.scheduleWeatherDebugFallback(weather ?? DEFAULT_SIMULATOR_WEATHER, {
        quiet: options.quiet !== false
      })
      if (options.quiet === false) {
        if (bridgeSent) {
          this.host.appendLog(
            `synced simulator weather via phone bridge: ${this.parseSimulatorTemperatureC(weather?.temperatureC) ?? "?"}°C ${weather?.condition || "clear"}`
          )
        } else {
          this.host.appendLog("skipped simulator weather sync: phone bridge is not connected")
        }
      }
    }, 150)
  }

  scheduleWeatherDebugFallback(
    weather: WeatherSimulatorSettings,
    options: QuietOptions = {}
  ): void {
    if (this.host.weatherDebugFallbackTimer != null) {
      window.clearTimeout(this.host.weatherDebugFallbackTimer)
    }

    this.host.weatherDebugFallbackTimer = window.setTimeout(() => {
      this.host.weatherDebugFallbackTimer = null
      const sent = this.enqueueWeatherDebugPush(weather, {quiet: true, force: true})
      if (sent && options.quiet === false) {
        this.host.appendLog(
          `pushed simulator weather to watch: ${this.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
        )
      }
    }, 1500)
  }

  scheduleWeatherDebugAckTimeout(): void {
    if (this.host.weatherDebugAckTimer != null) {
      window.clearTimeout(this.host.weatherDebugAckTimer)
    }

    this.host.weatherDebugAckTimer = window.setTimeout(() => {
      this.host.weatherDebugAckTimer = null
      if (!this.host.weatherDebugInFlight) return
      this.host.weatherDebugInFlight = false
      this.drainWeatherDebugQueue()
    }, 2500)
  }

  weatherDebugQueueKey(weather: WeatherSimulatorSettings | null | undefined): string {
    return JSON.stringify({
      temperatureC: this.parseSimulatorTemperatureC(weather?.temperatureC),
      condition: weather?.condition || "clear"
    })
  }

  enqueueWeatherDebugPush(
    weather: WeatherSimulatorSettings,
    options: WeatherDebugOptions = {}
  ): boolean {
    if (!this.simulatorWeatherEnabled()) return false
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

    const resolved =
      weather && typeof weather === "object" ? weather : DEFAULT_SIMULATOR_WEATHER
    const queueKey = this.weatherDebugQueueKey(resolved)
    if (!options.force && queueKey === this.host.lastSentWeatherJson) {
      return false
    }

    this.host.weatherDebugQueue = this.host.weatherDebugQueue.filter(
      item => item.queueKey !== queueKey
    )
    this.host.weatherDebugQueue.push({weather: resolved, options, queueKey})
    return this.drainWeatherDebugQueue()
  }

  drainWeatherDebugQueue(): boolean {
    if (this.host.weatherDebugInFlight || this.host.weatherDebugQueue.length === 0) {
      return false
    }

    const item = this.host.weatherDebugQueue.shift()
    if (!item) return false

    this.host.weatherDebugInFlight = true
    this.host.weatherDebugInFlightAt = Date.now()
    this.host.pendingWeatherRetry = item.weather
    const sent = this.pushWeatherDebugAppMessage(item.weather, {quiet: true})
    if (!sent) {
      this.host.weatherDebugInFlight = false
      this.host.weatherDebugQueue.unshift(item)
      return false
    }

    this.scheduleWeatherDebugAckTimeout()
    return true
  }

  logWeatherTrace(bytes: ArrayBuffer): void {
    if (!this.host.emulatorDebugEnabled()) return
    try {
      const trace = JSON.parse(new TextDecoder().decode(bytes)) as Record<string, unknown>
      const temp = trace.temperatureC ?? (trace.weather as WeatherSimulatorSettings)?.temperatureC ?? "?"
      const condition =
        trace.condition ?? (trace.weather as WeatherSimulatorSettings)?.condition ?? "clear"
      const detail = trace.detail ? ` (${trace.detail})` : ""
      this.host.appendLog(`weather trace [${trace.stage}]: ${temp}°C ${condition}${detail}`)
    } catch {
      this.host.appendLog("weather trace: could not decode trace frame")
    }
  }

  resetWeatherDebugQueueIfStuck(reason: string): boolean {
    if (!this.host.weatherDebugInFlight) return false
    const ageMs = Date.now() - this.host.weatherDebugInFlightAt
    if (ageMs < 2500) return false
    this.host.weatherDebugInFlight = false
    this.host.pendingWeatherRetry = null
    if (this.host.weatherDebugAckTimer != null) {
      window.clearTimeout(this.host.weatherDebugAckTimer)
      this.host.weatherDebugAckTimer = null
    }
    this.host.appendLog(
      `weather trace [queue_reset]: prior inject ack timed out (${reason}, ${ageMs}ms)`
    )
    return true
  }

  weatherConditionWireCode(condition: string | undefined): number {
    const normalized = String(condition || "clear")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "")
    return WEATHER_CONDITION_WIRE_CODES[normalized] ?? WEATHER_CONDITION_WIRE_CODES.clear!
  }

  parseSimulatorTemperatureC(value: unknown): number | null {
    if (value === null || value === undefined || value === "") return null
    const parsed = Number(value)
    return Number.isFinite(parsed) ? Math.round(parsed) : null
  }

  resolveWeatherSimulatorSettings(
    settings: SimulatorSettings | null = this.host.simulatorSettings
  ): WeatherSimulatorSettings | null {
    if (!settings || typeof settings !== "object") {
      return this.simulatorWeatherEnabled() ? DEFAULT_SIMULATOR_WEATHER : null
    }

    const record = settings as Record<string, unknown>
    const nested = record.weather
    if (nested && typeof nested === "object" && !Array.isArray(nested)) {
      const w = nested as Record<string, unknown>
      return {
        temperatureC: (w.temperatureC ??
          record.weather_temperatureC ??
          DEFAULT_SIMULATOR_WEATHER.temperatureC) as number | string | undefined,
        condition: String(
          w.condition ?? record.weather_condition ?? DEFAULT_SIMULATOR_WEATHER.condition
        )
      }
    }

    if (
      record.weather_temperatureC != null ||
      record.weather_condition != null ||
      record.weather_humidityPercent != null ||
      record.weather_pressureHpa != null ||
      record.weather_windKph != null
    ) {
      return {
        temperatureC: (record.weather_temperatureC ??
          DEFAULT_SIMULATOR_WEATHER.temperatureC) as number | string | undefined,
        condition: String(record.weather_condition || DEFAULT_SIMULATOR_WEATHER.condition)
      }
    }

    return this.simulatorWeatherEnabled() ? DEFAULT_SIMULATOR_WEATHER : null
  }

  scheduleWeatherSimulatorInject(reason: string): void {
    if (!this.simulatorWeatherEnabled()) return
    this.host.weatherInjectTimers.forEach(timerId => window.clearTimeout(timerId))
    const timerId = window.setTimeout(() => {
      this.host.weatherInjectTimers = this.host.weatherInjectTimers.filter(id => id !== timerId)
      this.injectWeatherSimulatorSettings(reason)
    }, 2000)
    this.host.weatherInjectTimers = [timerId]
  }

  injectWeatherSimulatorSettings(reason: string): void {
    if (!this.simulatorWeatherEnabled()) return
    const weather = this.resolveWeatherSimulatorSettings()
    if (!weather) return
    const sent = this.pushWeatherDebugAppMessage(weather, {quiet: true})
    if (sent) {
      this.host.appendLog(
        `injected simulator weather (${reason}): ${this.parseSimulatorTemperatureC(weather.temperatureC) ?? "?"}°C ${weather.condition || "clear"}`
      )
    }
  }

  pushWeatherDebugAppMessage(
    weather: WeatherSimulatorSettings,
    options: QuietOptions = {}
  ): boolean {
    if (!this.simulatorWeatherEnabled()) return false
    const resolved =
      weather && typeof weather === "object" ? weather : DEFAULT_SIMULATOR_WEATHER
    const temperatureC = this.parseSimulatorTemperatureC(resolved.temperatureC)
    const conditionWire = this.weatherConditionWireCode(resolved.condition)
    const entries: Array<{key: number; type: string; value: number}> = []

    if (temperatureC != null) {
      entries.push({key: DEBUG_SIMULATOR.weatherTemperatureC, type: "int", value: temperatureC})
    }
    entries.push({
      key: DEBUG_SIMULATOR.weatherConditionWire,
      type: "int",
      value: conditionWire
    })

    return this.host.sendDebugAppMessage(entries, options)
  }

  sendWeatherSimulatorSettings(
    weather: WeatherSimulatorSettings,
    options: WeatherDebugOptions = {}
  ): boolean {
    return this.enqueueWeatherDebugPush(weather, options)
  }

  sendSimulatorSettingsToPhoneBridge(
    settings: SimulatorSettingsPayload | null = null
  ): boolean {
    const payload = settings ?? this.simulatorSettingsPayload()
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
