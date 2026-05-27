import type {EmulatorSessionInfo, SimulatorSettings} from "./emulator"
import type {
  QemuSettingsApplyRecord,
  SimulatorSettingsPayload,
  WeatherDebugQueueItem,
  WeatherSimulatorSettings
} from "./emulator_options"
import type {EmbeddedEmulatorHostSurface} from "./emulator_host"

/** Host surface required by EmulatorSimulatorDelivery (mutable simulator state). */
export type SimulatorDeliveryHost = EmbeddedEmulatorHostSurface & {
  simulatorSettings: SimulatorSettings | null
  simulatorSettingsSource: string | null
  simulatorSettingsAppliedAt: number
  lastAppliedSimulatorSettingsJson: string | null
  lastQemuSettingsApply: QemuSettingsApplyRecord | null
  _simulatorCapabilities?: Set<string>
  phoneSocket: WebSocket | null
  weatherInjectTimers: ReturnType<typeof setTimeout>[]
  weatherPushTimer: ReturnType<typeof setTimeout> | null
  weatherPushRetryTimers: ReturnType<typeof setTimeout>[]
  weatherDebugQueue: WeatherDebugQueueItem[]
  weatherDebugInFlight: boolean
  weatherDebugInFlightAt: number
  weatherDebugAckTimer: ReturnType<typeof setTimeout> | null
  weatherDebugFallbackTimer: ReturnType<typeof setTimeout> | null
  pendingWeatherRetry: WeatherSimulatorSettings | null
  sendQemu: (protocol: number, payload: number[]) => void
  sendDebugAppMessage: (
    entries: Array<{key: number; type: string; value: number | string}>,
    options?: {quiet?: boolean}
  ) => boolean
}
