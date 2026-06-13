export type WatchFaultKind = "oom" | "memory" | "crash"

export type WatchFault = {
  kind: WatchFaultKind
  headline: string
  detail: string
  elmcRcCode?: number
  elmcRcLine?: number
}

const APP_LOG_BODY = /AppLog(?:\s+\S+)*\s+[^:]+:\s*(.+)$/i

const ELMC_RC_CODES: Record<number, string> = {
  0: "RC_SUCCESS",
  1: "RC_ERR_OUT_OF_MEMORY",
  2: "RC_ERR_INVALID_ARG",
  3: "RC_ERR_UNSUPPORTED",
  4: "RC_ERR_MISSING_CALLBACK",
  5: "RC_ERR_MALFORMED_TUPLE",
  6: "RC_ERR_MALFORMED_CMD",
  7: "RC_ERR_MALFORMED_VIEW",
  8: "RC_ERR_MALFORMED_SUB",
  9: "RC_ERR_SCENE_BUFFER_OVERFLOW",
  10: "RC_ERR_SCENE_DECODE",
  11: "RC_ERR_SCENE_DEPTH_LIMIT",
  12: "RC_ERR_RENDER_ABORT"
}

export function elmcRcName(code: number): string {
  return ELMC_RC_CODES[code] ?? `RC_${code}`
}

export function watchFaultMessageBody(message: string): string {
  const appLog = message.match(APP_LOG_BODY)
  return (appLog?.[1] ?? message).trim()
}

function classifyElmcRcFailure(body: string): WatchFault | null {
  const match =
    body.match(/ELMC\s+worker\s+\w+\s+RC\s+(\d+)\s+line\s+(\d+)/i) ??
    body.match(/ELMC\s+[^R]*RC\s+(\d+)\s+line\s+(\d+)/i) ??
    body.match(/ELMC\s+[^R]*RC\s+(\d+)/i)

  if (!match) return null

  const code = Number.parseInt(match[1] ?? "", 10)
  if (!Number.isFinite(code) || code === 0) return null

  const line = match[2] ? Number.parseInt(match[2], 10) : null
  const name = elmcRcName(code)
  const kind: WatchFaultKind = code === 1 ? "oom" : "crash"
  const detail =
    line != null && Number.isFinite(line)
      ? `${name} (code ${code}) at source line ${line}`
      : `${name} (code ${code})`

  return {
    kind,
    headline: code === 1 ? "Watch app ran out of memory" : "Watch app reported an Elm runtime error",
    detail,
    elmcRcCode: code,
    elmcRcLine: line != null && Number.isFinite(line) ? line : undefined
  }
}

export function classifyWatchFault(message: string): WatchFault | null {
  const body = watchFaultMessageBody(message)
  if (!body) return null

  const rcFault = classifyElmcRcFailure(body)
  if (rcFault) return rcFault

  if (/ELMC allocation failed/i.test(body)) {
    const bytes = body.match(/\((\d+)\s*bytes\)/i)?.[1]
    const detail = bytes ? `ELMC allocation failed (${bytes} bytes)` : body
    return {
      kind: "oom",
      headline: "Watch app ran out of memory",
      detail
    }
  }

  if (/insufficient memory/i.test(body)) {
    return {
      kind: "memory",
      headline: "Watch app ran out of memory",
      detail: body
    }
  }

  if (/App fault!/i.test(body)) {
    return {
      kind: "crash",
      headline: "Watch app crashed",
      detail: body
    }
  }

  return null
}
