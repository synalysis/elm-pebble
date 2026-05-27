declare module "phoenix" {
  export type ConnectionState = "connecting" | "open" | "closing" | "closed"

  export class Socket {
    constructor(endPoint: string, opts?: Record<string, unknown>)
    connect(): void
    disconnect(callback?: () => void, code?: number, reason?: string): void
    connectionState(): ConnectionState
    onOpen(callback: () => void): void
    onClose(callback: () => void): void
    onError(callback: (error: unknown) => void): void
    channel(topic: string, params?: Record<string, unknown>): Channel
  }

  export type ChannelPushReply = {
    receive(status: "ok", callback: (resp: unknown) => void): ChannelPushReply
    receive(status: "error", callback: (resp: unknown) => void): ChannelPushReply
    receive(status: "timeout", callback: () => void): ChannelPushReply
  }

  export class Channel {
    join(timeout?: number): ChannelPushReply
    leave(timeout?: number): ChannelPushReply
    on(event: string, callback: (payload: unknown) => void): void
    onError(callback: () => void): void
    onClose(callback: () => void): void
    push(event: string, payload: unknown, timeout?: number): ChannelPushReply
  }
}
