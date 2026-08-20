/** Browser contracts for embedded emulator HTTP/JSON (snake_case from Elixir/Jason). */

export type EmulatorScreen = {
  width: number
  height: number
}

export type ElmcRuntimeStatsWire = {
  scene_bytes: number
  scene_cmds: number
  scene_cap: number
  heap_free: number
  heap_free_min: number
}

export type EmulatorSessionInfo = {
  id: string
  token: string
  project_slug: string
  platform: string
  artifact_path: string
  app_uuid: string | null
  has_phone_companion: boolean
  has_companion_preferences: boolean
  install_path: string
  request_app_logs_path: string
  vnc_path: string
  phone_path: string
  ping_path: string
  kill_path: string
  screen: EmulatorScreen
  controls: string[]
  backend_enabled: boolean
  display_ready: boolean
  phone_bridge_ready: boolean
  installing: boolean
  runtime_stats?: ElmcRuntimeStatsWire | null
}

export type PingResponse = EmulatorSessionInfo & {
  alive?: boolean
}

export type LaunchRequest = {
  slug: string
  platform: string
}

export type ApplySettingsResult = {
  applied: number
  protocols: number[]
}

export type ApiErrorBody = {
  error?: string
}

export type SimulatorSettings = Record<string, unknown>

export type QemuCommand = {
  protocol: number
  payload: number[]
}
