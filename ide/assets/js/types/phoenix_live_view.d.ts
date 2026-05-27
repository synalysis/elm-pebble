declare module "phoenix_live_view" {
  import type {Socket} from "phoenix"

  export class LiveSocket {
    constructor(
      url: string,
      socket: typeof Socket,
      opts?: Record<string, unknown>
    )
    connect(): void
    disconnect(callback?: () => void): void
    enableDebug(): void
    disableDebug(): void
    enableLatencySim(ms: number): void
    disableLatencySim(): void
  }

  export interface ViewHookInterface {
    el: HTMLElement
    liveSocket: LiveSocket
    pushEvent(event: string, payload: Record<string, unknown>, onReply?: (reply: unknown) => void): void
    handleEvent(event: string, callback: (payload: unknown) => void): void
    mounted(): void
    updated(): void
    destroyed(): void
    disconnected(): void
    reconnected(): void
    beforeUpdate(): void
    afterUpdate(): void
  }

  export type ViewHook = Partial<ViewHookInterface> & {
    destroyedBeforeReady?: boolean
    [key: string]: unknown
  }
}
