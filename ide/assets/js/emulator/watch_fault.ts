export type WatchFaultKind = "oom" | "memory" | "crash"

export type WatchFault = {
  kind: WatchFaultKind
  headline: string
  detail: string
}

const APP_LOG_BODY = /AppLog(?:\s+\S+)*\s+[^:]+:\s*(.+)$/i

export function watchFaultMessageBody(message: string): string {
  const appLog = message.match(APP_LOG_BODY)
  return (appLog?.[1] ?? message).trim()
}

export function classifyWatchFault(message: string): WatchFault | null {
  const body = watchFaultMessageBody(message)
  if (!body) return null

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
