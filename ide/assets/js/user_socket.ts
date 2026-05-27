import {Socket, type ConnectionState} from "phoenix"

let socket: Socket | null = null

function csrfToken(): string {
  const meta = document.querySelector("meta[name='csrf-token']")
  return meta?.getAttribute("content") ?? ""
}

export type UserSocketLogFn = (message: string) => void

export type GetUserSocketOpts = {
  onLog?: UserSocketLogFn
}

/**
 * Shared Phoenix user socket for IDE channels (LSP, emulator VNC, …).
 * Reuses one connection per page when possible.
 */
export function getUserSocket({onLog}: GetUserSocketOpts = {}): Socket {
  if (socket && socket.connectionState() !== "closed") return socket

  socket = new Socket("/socket", {
    params: {_csrf_token: csrfToken()},
    longPollFallbackMs: 2500
  })

  if (typeof onLog === "function") {
    socket.onOpen(() => onLog("Phoenix user socket open"))
    socket.onError(error => {
      const msg =
        error && typeof error === "object" && "message" in error
          ? String((error as {message: unknown}).message)
          : String(error ?? "unknown")
      onLog(`Phoenix user socket error: ${msg}`)
    })
    socket.onClose(() => onLog("Phoenix user socket closed"))
  }

  socket.connect()
  return socket
}

export type WaitForSocketOpts = {
  onLog?: UserSocketLogFn
}

export function waitForUserSocketOpen(
  sock: Socket,
  timeoutMs: number,
  {onLog}: WaitForSocketOpts = {}
): Promise<void> {
  return new Promise((resolve, reject) => {
    const state: ConnectionState = sock.connectionState()
    if (state === "open") return resolve()
    if (state === "closed") {
      return reject(new Error("Phoenix user socket is closed"))
    }

    let settled = false
    const finish = (error: Error | null) => {
      if (settled) return
      settled = true
      window.clearTimeout(timer)
      if (error) reject(error)
      else resolve()
    }

    const timer = window.setTimeout(() => {
      finish(
        new Error(
          `Phoenix user socket did not open within ${timeoutMs / 1000}s (state=${sock.connectionState()})`
        )
      )
    }, timeoutMs)

    sock.onOpen(() => finish(null))
    sock.onError(error => {
      if (typeof onLog === "function") {
        const msg =
          error && typeof error === "object" && "message" in error
            ? String((error as {message: unknown}).message)
            : String(error ?? "unknown")
        onLog(`Phoenix user socket error before open: ${msg}`)
      }
      finish(
        new Error(
          `Phoenix user socket error before open: ${
            error && typeof error === "object" && "message" in error
              ? String((error as {message: unknown}).message)
              : String(error ?? "unknown")
          }`
        )
      )
    })
    sock.onClose(() => {
      if (sock.connectionState() !== "open") {
        finish(new Error("Phoenix user socket closed before open"))
      }
    })
  })
}

export function disconnectUserSocket(): void {
  if (!socket) return
  try {
    socket.disconnect()
  } catch {
    // Socket may already be disconnected.
  }
  socket = null
}
