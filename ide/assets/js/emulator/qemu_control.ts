/** Pebble QEMU control protocol — shared by embedded and WASM emulator hosts. */

import type {SimulatorSettings} from "../types/emulator"

export const BUTTONS = {back: 0, up: 1, select: 2, down: 3} as const

export const QEMU = {
  tap: 2,
  bluetooth: 3,
  battery: 5,
  button: 8,
  timeFormat: 9,
  timelinePeek: 10,
  accel: 11,
  compass: 12
} as const

export type CompassSettings = {
  compass_heading_deg?: number
  compass_valid?: boolean
}

export function clampPercent(percent: unknown): number {
  const value = Number(percent)
  if (!Number.isFinite(value)) return 0
  return Math.max(0, Math.min(100, Math.round(value)))
}

export function encodeBattery(percent: unknown, charging: boolean): number[] {
  return [clampPercent(percent), charging ? 1 : 0]
}

export function encodeBluetooth(connected: boolean): number[] {
  return [connected ? 1 : 0]
}

export function encodeTimeFormat(clock24h: boolean): number[] {
  return [clock24h ? 1 : 0]
}

export function encodeTimelinePeek(enabled: boolean): number[] {
  return [enabled ? 1 : 0]
}

export function signedInt16Bytes(value: number): number[] {
  const clamped = Math.max(-32768, Math.min(32767, value | 0))
  const unsigned = clamped < 0 ? clamped + 65536 : clamped
  return [(unsigned >> 8) & 0xff, unsigned & 0xff]
}

export function encodeAccel(x: number, y: number, z: number): number[] {
  return [...signedInt16Bytes(x), ...signedInt16Bytes(y), ...signedInt16Bytes(z)]
}

export function encodeCompass(settings: CompassSettings = {}): number[] {
  const degrees = Math.max(0, Math.min(360, Number(settings.compass_heading_deg ?? 0)))
  const valid = settings.compass_valid ? 1 : 0
  const degInt = Math.round(degrees)
  return [(degInt >> 8) & 0xff, degInt & 0xff, valid]
}

export function qemuCommandsFromSimulatorSettings(settings: SimulatorSettings = {}): {
  protocol: number
  payload: number[]
}[] {
  const commands: {protocol: number; payload: number[]}[] = []

  if (settings.battery_percent != null || settings.charging != null) {
    commands.push({
      protocol: QEMU.battery,
      payload: encodeBattery(settings.battery_percent, !!settings.charging)
    })
  }

  if (settings.connected != null) {
    commands.push({protocol: QEMU.bluetooth, payload: encodeBluetooth(!!settings.connected)})
  }

  if (settings.clock_24h != null) {
    commands.push({protocol: QEMU.timeFormat, payload: encodeTimeFormat(!!settings.clock_24h)})
  }

  if (settings.timeline_peek != null) {
    commands.push({protocol: QEMU.timelinePeek, payload: encodeTimelinePeek(!!settings.timeline_peek)})
  }

  if (settings.compass_heading_deg != null || settings.compass_valid != null) {
    commands.push({protocol: QEMU.compass, payload: encodeCompass(settings as CompassSettings)})
  }

  return commands
}

export function applySimulatorSettingsToQemu(
  sendQemu: (protocol: number, payload: number[]) => void,
  settings: SimulatorSettings = {}
): void {
  for (const {protocol, payload} of qemuCommandsFromSimulatorSettings(settings)) {
    sendQemu(protocol, payload)
  }
}
