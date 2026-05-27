export function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
}

export async function postJSON(url, body = {}, {timeoutMs} = {}) {
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
    const data = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(data.error || response.statusText)
    return data
  } catch (error) {
    if (controller?.signal.aborted) {
      throw new Error(`Request timed out after ${Math.round(timeoutMs / 1000)}s`)
    }

    throw error
  } finally {
    if (timer) clearTimeout(timer)
  }
}

export function websocketURL(path) {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
  return `${protocol}//${window.location.host}${path}`
}
