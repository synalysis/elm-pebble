import type {ApiErrorBody} from "../types/emulator"

export function csrfToken(): string {
  return document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
}

export type PostJSONOptions = {
  timeoutMs?: number
}

export async function postJSON<T = Record<string, unknown>>(
  url: string,
  body: Record<string, unknown> = {},
  {timeoutMs}: PostJSONOptions = {}
): Promise<T> {
  const controller = timeoutMs ? new AbortController() : null
  const timer =
    controller &&
    setTimeout(() => {
      controller.abort()
    }, timeoutMs)

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {"content-type": "application/json", "x-csrf-token": csrfToken()},
      body: JSON.stringify(body),
      signal: controller?.signal
    })
    const data = (await response.json().catch(() => ({}))) as T & ApiErrorBody
    if (!response.ok) {
      const err = data as ApiErrorBody
      throw new Error(err.error || response.statusText)
    }
    return data
  } catch (error) {
    if (controller?.signal.aborted && timeoutMs) {
      throw new Error(`Request timed out after ${Math.round(timeoutMs / 1000)}s`)
    }

    throw error
  } finally {
    if (timer) clearTimeout(timer)
  }
}

export function websocketURL(path: string): string {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
  return `${protocol}//${window.location.host}${path}`
}
