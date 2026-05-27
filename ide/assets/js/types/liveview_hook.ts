/** Narrow LiveView hook `this` for IDE hooks (not full Phoenix.ViewHook). */
export type HookContext = {
  el: HTMLElement
  destroyedBeforeReady?: boolean
  destroyed?: boolean
  pushEvent(event: string, payload: Record<string, unknown>, onReply?: (reply: unknown) => void): void
  handleEvent(event: string, callback: (payload: unknown) => void): void
  [key: string]: unknown
}
