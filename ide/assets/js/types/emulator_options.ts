/** Option bags for embedded emulator client modules. */

export type SimulatorSettingsOptions = {
  source?: string
  quiet?: boolean
  syncCompanion?: boolean
}

export type QuietOptions = {
  quiet?: boolean
}

export type WeatherDebugOptions = QuietOptions & {
  force?: boolean
}

export type WeatherSimulatorSettings = {
  temperatureC?: number | string
  condition?: string
}

export type SimulatorSettingsPayload = {
  weather?: WeatherSimulatorSettings
  [key: string]: unknown
}

export type QemuSettingsApplyRecord = {
  count: number
  source: string
  protocols: number[]
}

export type WeatherDebugQueueItem = {
  weather: WeatherSimulatorSettings
  options: WeatherDebugOptions
  queueKey: string
}
