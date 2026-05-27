import {Socket} from "phoenix"

let socket = null

function csrfToken() {
  const meta = document.querySelector("meta[name='csrf-token']")
  return meta?.getAttribute("content") ?? ""
}

/**
 * Shared Phoenix user socket for IDE channels (LSP, emulator VNC, …).
 * Reuses one connection per page when possible.
 */
export function getUserSocket({onLog} = {}) {
  if (socket && socket.connectionState() !== "closed") return socket

  socket = new Socket("/socket", {
    params: {_csrf_token: csrfToken()},
    longPollFallbackMs: 2500
  })

  if (typeof onLog === "function") {
    socket.onOpen(() => onLog("Phoenix user socket open"))
    socket.onError(error => onLog(`Phoenix user socket error: ${error?.message || error || "unknown"}`))
    socket.onClose(() => onLog("Phoenix user socket closed"))
  }

  socket.connect()
  return socket
}

export function waitForUserSocketOpen(socket, timeoutMs, {onLog} = {}) {
  return new Promise((resolve, reject) => {
    const state = socket.connectionState()
    if (state === "open") return resolve()
    if (state === "closed") {
      return reject(new Error("Phoenix user socket is closed"))
    }

    let settled = false
    const finish = (error, ok = false) => {
      if (settled) return
      settled = true
      window.clearTimeout(timer)
      if (error) reject(error)
      else resolve(ok)
    }

    const timer = window.setTimeout(() => {
      finish(
        new Error(
          `Phoenix user socket did not open within ${timeoutMs / 1000}s (state=${socket.connectionState()})`
        )
      )
    }, timeoutMs)

    socket.onOpen(() => finish(null, true))
    socket.onError(error => {
      if (typeof onLog === "function") {
        onLog(`Phoenix user socket error before open: ${error?.message || error || "unknown"}`)
      }
      finish(new Error(`Phoenix user socket error before open: ${error?.message || error || "unknown"}`))
    })
    socket.onClose(() => {
      if (socket.connectionState() !== "open") {
        finish(new Error("Phoenix user socket closed before open"))
      }
    })
  })
}

export function disconnectUserSocket() {
  if (!socket) return
  try {
    socket.disconnect()
  } catch (_error) {
    // Socket may already be disconnected.
  }
  socket = null
}
