/** Declared watch runtime watermarks (`elmc-stats` AppLog contract). */

export type ElmcRuntimeStats = {
  sceneBytes: number
  sceneCmds: number
  sceneCap: number
  heapFree: number
  heapFreeMin: number
}

const STATS_PREFIX = "elmc-stats"
const INT_KEYS = {
  scene_bytes: "sceneBytes",
  scene_cmds: "sceneCmds",
  scene_cap: "sceneCap",
  heap_free: "heapFree",
  heap_free_min: "heapFreeMin"
} as const

type IntField = (typeof INT_KEYS)[keyof typeof INT_KEYS]

export function appLogMessageBody(message: string): string {
  const appLog = message.match(/AppLog(?:\s+\S+)*\s+[^:]+:\s*(.+)$/)
  return appLog?.[1] ?? message
}

export function parseElmcRuntimeStats(message: string): ElmcRuntimeStats | null {
  const body = appLogMessageBody(message)
  const start = body.indexOf(STATS_PREFIX)
  if (start < 0) return null

  const rest = body.slice(start + STATS_PREFIX.length)
  const stats: Partial<ElmcRuntimeStats> = {}
  for (const token of rest.trim().split(/\s+/)) {
    const eq = token.indexOf("=")
    if (eq <= 0) continue
    const key = token.slice(0, eq)
    const field = INT_KEYS[key as keyof typeof INT_KEYS]
    if (!field) continue
    const value = Number.parseInt(token.slice(eq + 1), 10)
    if (!Number.isFinite(value)) continue
    stats[field as IntField] = value
  }

  if (
    stats.sceneBytes == null ||
    stats.sceneCmds == null ||
    stats.sceneCap == null ||
    stats.heapFree == null ||
    stats.heapFreeMin == null
  ) {
    return null
  }

  return stats as ElmcRuntimeStats
}

export function runtimeStatsFromWire(value: unknown): ElmcRuntimeStats | null {
  if (!value || typeof value !== "object") return null
  const rec = value as Record<string, unknown>
  const sceneBytes = asWireInt(rec.scene_bytes ?? rec.sceneBytes)
  const sceneCmds = asWireInt(rec.scene_cmds ?? rec.sceneCmds)
  const sceneCap = asWireInt(rec.scene_cap ?? rec.sceneCap)
  const heapFree = asWireInt(rec.heap_free ?? rec.heapFree)
  const heapFreeMin = asWireInt(rec.heap_free_min ?? rec.heapFreeMin)
  if (
    sceneBytes == null ||
    sceneCmds == null ||
    sceneCap == null ||
    heapFree == null ||
    heapFreeMin == null
  ) {
    return null
  }
  return {sceneBytes, sceneCmds, sceneCap, heapFree, heapFreeMin}
}

function asWireInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.trunc(value)
  if (typeof value === "string") {
    const parsed = Number.parseInt(value, 10)
    if (Number.isFinite(parsed)) return parsed
  }
  return null
}

export function mergeElmcRuntimeStats(
  current: ElmcRuntimeStats | null,
  next: ElmcRuntimeStats
): ElmcRuntimeStats {
  if (!current) return next
  return {
    sceneBytes: Math.max(current.sceneBytes, next.sceneBytes),
    sceneCmds: Math.max(current.sceneCmds, next.sceneCmds),
    sceneCap: Math.max(current.sceneCap, next.sceneCap),
    heapFree: next.heapFree,
    heapFreeMin:
      current.heapFreeMin > 0 ? Math.min(current.heapFreeMin, next.heapFreeMin) : next.heapFreeMin
  }
}

export function renderElmcRuntimeStats(
  root: ParentNode | null,
  stats: ElmcRuntimeStats | null,
  kind: "emulator" | "wasm"
): void {
  if (!root) return
  const panel = root.querySelector(`[data-runtime-stats="${kind}"]`)
  if (!(panel instanceof HTMLElement)) return
  const empty = panel.querySelector("[data-runtime-stats-empty]")
  const values = panel.querySelector("[data-runtime-stats-values]")
  const scene = panel.querySelector("[data-runtime-stats-scene]")
  const cmds = panel.querySelector("[data-runtime-stats-cmds]")
  const heap = panel.querySelector("[data-runtime-stats-heap]")
  if (empty instanceof HTMLElement) empty.hidden = stats != null
  if (values instanceof HTMLElement) values.hidden = stats == null
  if (!stats) return
  if (scene) {
    scene.textContent =
      stats.sceneCap > 0 ? `${stats.sceneBytes} / ${stats.sceneCap} B` : `${stats.sceneBytes} B`
  }
  if (cmds) cmds.textContent = String(stats.sceneCmds)
  if (heap) {
    heap.textContent =
      stats.heapFreeMin > 0 && stats.heapFreeMin !== stats.heapFree
        ? `${stats.heapFree} B (min ${stats.heapFreeMin})`
        : `${stats.heapFree} B`
  }
}
