/** Pebble QEMU control protocol — shared by embedded and WASM emulator hosts. */

export const BUTTONS = {back: 0, up: 1, select: 2, down: 3}

export const QEMU = {
  tap: 2,
  bluetooth: 3,
  battery: 5,
  button: 8,
  timeFormat: 9,
  timelinePeek: 10,
  accel: 11,
  compass: 12
}

export function clampPercent(percent) {
  const value = Number(percent)
  if (!Number.isFinite(value)) return 0
  return Math.max(0, Math.min(100, Math.round(value)))
}

export function encodeBattery(percent, charging) {
  return [clampPercent(percent), charging ? 1 : 0]
}

export function encodeBluetooth(connected) {
  return [connected ? 1 : 0]
}

export function encodeTimeFormat(clock24h) {
  return [clock24h ? 1 : 0]
}

export function encodeTimelinePeek(enabled) {
  return [enabled ? 1 : 0]
}

export function signedInt16Bytes(value) {
  const clamped = Math.max(-32768, Math.min(32767, value | 0))
  const unsigned = clamped < 0 ? clamped + 65536 : clamped
  return [(unsigned >> 8) & 0xff, unsigned & 0xff]
}

export function encodeAccel(x, y, z) {
  return [...signedInt16Bytes(x), ...signedInt16Bytes(y), ...signedInt16Bytes(z)]
}

export function encodeCompass(settings = {}) {
  const degrees = Math.max(0, Math.min(360, Number(settings.compass_heading_deg ?? 0)))
  const valid = settings.compass_valid ? 1 : 0
  const degInt = Math.round(degrees)
  return [(degInt >> 8) & 0xff, degInt & 0xff, valid]
}

/**
 * Maps simulator settings to QEMU control packets (protocol + byte payload).
 * @param {Record<string, unknown>} settings
 * @returns {{protocol: number, payload: number[]}[]}
 */
export function qemuCommandsFromSimulatorSettings(settings = {}) {
  const commands = []

  if (settings.battery_percent != null || settings.charging != null) {
    commands.push({
      protocol: QEMU.battery,
      payload: encodeBattery(settings.battery_percent ?? 88, !!settings.charging)
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
    commands.push({protocol: QEMU.compass, payload: encodeCompass(settings)})
  }

  return commands
}

/**
 * Pushes QEMU commands derived from simulator settings.
 * @param {(protocol: number, payload: number[]) => void} sendQemu
 * @param {Record<string, unknown>} settings
 */
export function applySimulatorSettingsToQemu(sendQemu, settings = {}) {
  for (const {protocol, payload} of qemuCommandsFromSimulatorSettings(settings)) {
    sendQemu(protocol, payload)
  }
}
