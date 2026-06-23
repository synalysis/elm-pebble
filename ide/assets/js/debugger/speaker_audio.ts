export type SpeakerEffectWire = {
  seq?: number
  command?: SpeakerCommandWire
}

export type SpeakerCommandWire = {
  kind?: string
  variant?: string
  frequency_hz?: number
  duration_ms?: number
  volume?: number
  waveform?: number
  note_values?: number[]
  track_values?: number[]
}

export type SpeakerSampleWire = {
  index?: number
  url?: string
  format?: number
  base_midi_note?: number
  loop?: boolean
}

type ActiveVoice = {
  stopAt: number
  nodes: AudioNode[]
}

let audioContext: AudioContext | null = null
const activeVoices: ActiveVoice[] = []
let speakerSampleCatalog: SpeakerSampleWire[] = []
const speakerSampleBytes = new Map<number, ArrayBuffer>()

export function setSpeakerSampleCatalog(samples: SpeakerSampleWire[] | null | undefined): void {
  speakerSampleCatalog = Array.isArray(samples) ? samples : []
  speakerSampleBytes.clear()
}

function context(): AudioContext | null {
  if (typeof window === "undefined") return null
  if (audioContext) return audioContext
  const Ctx = window.AudioContext || (window as unknown as {webkitAudioContext?: typeof AudioContext}).webkitAudioContext
  if (!Ctx) return null
  audioContext = new Ctx()
  return audioContext
}

async function ensureRunning(ctx: AudioContext): Promise<void> {
  if (ctx.state === "suspended") await ctx.resume()
}

export function stopSpeakerPlayback(): void {
  const now = context()?.currentTime ?? 0
  for (const voice of activeVoices.splice(0, activeVoices.length)) {
    for (const node of voice.nodes) {
      try {
        if (node instanceof OscillatorNode) node.stop(now)
        node.disconnect()
      } catch {
        // already stopped
      }
    }
  }
}

function scheduleStop(nodes: AudioNode[], durationMs: number): void {
  const ctx = context()
  if (!ctx) return
  const stopAt = ctx.currentTime + durationMs / 1000
  activeVoices.push({stopAt, nodes})
}

function waveformType(waveform: number): OscillatorType {
  switch (waveform) {
    case 1:
      return "square"
    case 2:
      return "triangle"
    case 3:
      return "sawtooth"
    default:
      return "sine"
  }
}

function midiToHz(midi: number): number {
  return 440 * Math.pow(2, (midi - 69) / 12)
}

function playTone(cmd: SpeakerCommandWire): void {
  const ctx = context()
  if (!ctx) return
  const hz = cmd.frequency_hz ?? 440
  const durationMs = Math.max(1, cmd.duration_ms ?? 200)
  const volume = Math.min(1, Math.max(0, (cmd.volume ?? 50) / 100))
  const oscillator = ctx.createOscillator()
  const gain = ctx.createGain()
  oscillator.type = waveformType(cmd.waveform ?? 0)
  oscillator.frequency.value = hz
  gain.gain.value = volume * 0.2
  oscillator.connect(gain)
  gain.connect(ctx.destination)
  const start = ctx.currentTime
  oscillator.start(start)
  oscillator.stop(start + durationMs / 1000)
  scheduleStop([oscillator, gain], durationMs)
}

function playNoteSequence(noteValues: number[], globalVolume: number): void {
  const ctx = context()
  if (!ctx || noteValues.length < 4) return
  let offsetMs = 0
  for (let i = 0; i + 3 < noteValues.length; i += 4) {
    const midi = noteValues[i] ?? 0
    const waveform = noteValues[i + 1] ?? 0
    const durationMs = Math.max(1, noteValues[i + 2] ?? 100)
    const velocity = noteValues[i + 3] ?? 0
    if (midi <= 0) {
      offsetMs += durationMs
      continue
    }
    const volume =
      velocity > 0
        ? Math.min(1, Math.max(0, velocity / 127)) * 0.25
        : Math.min(1, Math.max(0, globalVolume / 100)) * 0.2
    const startAt = ctx.currentTime + offsetMs / 1000
    const oscillator = ctx.createOscillator()
    const gain = ctx.createGain()
    oscillator.type = waveformType(waveform)
    oscillator.frequency.value = midiToHz(midi)
    gain.gain.value = volume
    oscillator.connect(gain)
    gain.connect(ctx.destination)
    oscillator.start(startAt)
    oscillator.stop(startAt + durationMs / 1000)
    scheduleStop([oscillator, gain], offsetMs + durationMs)
    offsetMs += durationMs
  }
}

function playTracks(trackValues: number[], globalVolume: number): void {
  if (trackValues.length === 0) return
  let cursor = 0
  let offsetMs = 0
  while (cursor < trackValues.length) {
    const noteCount = trackValues[cursor] ?? 0
    cursor += 1
    if (cursor >= trackValues.length) break
    const sampleIndex = trackValues[cursor] ?? 0
    cursor += 1
    if (noteCount <= 0) break
    const slice = trackValues.slice(cursor, cursor + noteCount * 4)
    if (sampleIndex > 0) {
      void playSampleTrack(sampleIndex, slice, globalVolume, offsetMs)
    } else {
      playNoteSequenceAt(slice, globalVolume, offsetMs)
    }
    offsetMs += noteSequenceDurationMs(slice)
    cursor += noteCount * 4
  }
}

function playNoteSequenceAt(noteValues: number[], globalVolume: number, offsetMs: number): void {
  const ctx = context()
  if (!ctx || noteValues.length < 4) return
  let localOffset = 0
  for (let i = 0; i + 3 < noteValues.length; i += 4) {
    const midi = noteValues[i] ?? 0
    const waveform = noteValues[i + 1] ?? 0
    const durationMs = Math.max(1, noteValues[i + 2] ?? 100)
    const velocity = noteValues[i + 3] ?? 0
    if (midi <= 0) {
      localOffset += durationMs
      continue
    }
    const volume =
      velocity > 0
        ? Math.min(1, Math.max(0, velocity / 127)) * 0.25
        : Math.min(1, Math.max(0, globalVolume / 100)) * 0.2
    const startAt = ctx.currentTime + (offsetMs + localOffset) / 1000
    const oscillator = ctx.createOscillator()
    const gain = ctx.createGain()
    oscillator.type = waveformType(waveform)
    oscillator.frequency.value = midiToHz(midi)
    gain.gain.value = volume
    oscillator.connect(gain)
    gain.connect(ctx.destination)
    oscillator.start(startAt)
    oscillator.stop(startAt + durationMs / 1000)
    scheduleStop([oscillator, gain], offsetMs + localOffset + durationMs)
    localOffset += durationMs
  }
}

function sampleMeta(index: number): SpeakerSampleWire | undefined {
  return speakerSampleCatalog.find((row) => (row.index ?? 0) === index)
}

async function fetchSampleBytes(meta: SpeakerSampleWire): Promise<ArrayBuffer | null> {
  const index = meta.index ?? 0
  const cached = speakerSampleBytes.get(index)
  if (cached) return cached
  const url = meta.url ?? ""
  if (!url) return null
  const response = await fetch(url, {credentials: "same-origin"})
  if (!response.ok) return null
  const bytes = await response.arrayBuffer()
  speakerSampleBytes.set(index, bytes)
  return bytes
}

function sampleRateForFormat(format: number): number {
  switch (format) {
    case 1:
      return 16000
    case 3:
      return 16000
    default:
      return 8000
  }
}

function decodePcmToFloat32(bytes: ArrayBuffer, format: number): Float32Array {
  if (format === 0 || format === 1) {
    const view = new Uint8Array(bytes)
    const out = new Float32Array(view.length)
    for (let i = 0; i < view.length; i++) {
      out[i] = (view[i]! - 128) / 128
    }
    return out
  }

  const view = new DataView(bytes)
  const samples = Math.floor(bytes.byteLength / 2)
  const out = new Float32Array(samples)
  for (let i = 0; i < samples; i++) {
    out[i] = view.getInt16(i * 2, true) / 32768
  }
  return out
}

async function playSampleTrack(
  sampleIndex: number,
  noteValues: number[],
  globalVolume: number,
  offsetMs: number
): Promise<void> {
  const ctx = context()
  const meta = sampleMeta(sampleIndex)
  if (!ctx || !meta) return
  const bytes = await fetchSampleBytes(meta)
  if (!bytes) return
  await ensureRunning(ctx)

  const format = meta.format ?? 1
  const sampleRate = sampleRateForFormat(format)
  const pcm = decodePcmToFloat32(bytes, format)
  if (pcm.length === 0) return

  const midi = noteValues[0] ?? meta.base_midi_note ?? 60
  const durationMs = Math.max(1, noteValues[2] ?? Math.ceil((pcm.length / sampleRate) * 1000))
  const velocity = noteValues[3] ?? 0
  const volume =
    velocity > 0
      ? Math.min(1, Math.max(0, velocity / 127)) * 0.35
      : Math.min(1, Math.max(0, globalVolume / 100)) * 0.3
  const playbackRate =
    Math.pow(2, ((midi - (meta.base_midi_note ?? 60)) / 12)) * (ctx.sampleRate / sampleRate)

  const buffer = ctx.createBuffer(1, pcm.length, ctx.sampleRate)
  const channel = buffer.getChannelData(0)
  for (let i = 0; i < pcm.length; i++) {
    channel[i] = pcm[i]! * volume
  }

  const source = ctx.createBufferSource()
  source.buffer = buffer
  source.playbackRate.value = playbackRate
  source.connect(ctx.destination)
  const startAt = ctx.currentTime + offsetMs / 1000
  source.start(startAt, 0, Math.min(buffer.duration, durationMs / 1000))
  scheduleStop([source], offsetMs + durationMs)
}

export async function playSpeakerEffect(effect: SpeakerEffectWire | null | undefined): Promise<void> {
  const cmd = effect?.command
  if (!cmd || cmd.kind !== "cmd.effect.speaker") return
  const ctx = context()
  if (!ctx) return
  await ensureRunning(ctx)

  switch (cmd.variant) {
    case "play_tone":
      stopSpeakerPlayback()
      playTone(cmd)
      break
    case "play_notes":
      stopSpeakerPlayback()
      playNoteSequence(cmd.note_values ?? [], cmd.volume ?? 50)
      break
    case "play_tracks":
      stopSpeakerPlayback()
      playTracks(cmd.track_values ?? [], cmd.volume ?? 50)
      break
    case "stop":
      stopSpeakerPlayback()
      break
    default:
      break
  }
}

export function speakerPlaybackDurationMs(cmd: SpeakerCommandWire | null | undefined): number {
  if (!cmd || cmd.kind !== "cmd.effect.speaker") return 0

  switch (cmd.variant) {
    case "play_tone":
      return Math.max(1, cmd.duration_ms ?? 200)
    case "play_notes":
      return noteSequenceDurationMs(cmd.note_values ?? [])
    case "play_tracks":
      return tracksDurationMs(cmd.track_values ?? [])
    case "stop":
      return 0
    default:
      return 0
  }
}

function noteSequenceDurationMs(noteValues: number[]): number {
  let total = 0
  for (let i = 0; i + 3 < noteValues.length; i += 4) {
    const midi = noteValues[i] ?? 0
    const durationMs = Math.max(1, noteValues[i + 2] ?? 100)
    if (midi > 0) {
      total += durationMs
    } else {
      total += durationMs
    }
  }
  return total
}

function tracksDurationMs(trackValues: number[]): number {
  if (trackValues.length === 0) return 0
  let cursor = 0
  let total = 0
  while (cursor < trackValues.length) {
    const noteCount = trackValues[cursor] ?? 0
    cursor += 1
    if (cursor >= trackValues.length) break
    cursor += 1
    if (noteCount <= 0) break
    const slice = trackValues.slice(cursor, cursor + noteCount * 4)
    total += noteSequenceDurationMs(slice)
    cursor += noteCount * 4
  }
  return total
}
