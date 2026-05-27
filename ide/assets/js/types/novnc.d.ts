declare module "@novnc/novnc" {
  export type RFBEventType = string

  export type RFBEventDetail = {
    reason?: string
    status?: number
    clean?: boolean
  }

  export type RFBEvent = {
    detail?: RFBEventDetail
  }

  export type RFBInternalSocket = {
    _recvMessage?: (event: {data: ArrayBuffer}) => void
  }

  export class RFB {
    constructor(target: HTMLElement, urlOrChannel: string | unknown, options?: Record<string, unknown>)
    viewOnly: boolean
    scaleViewport: boolean
    resizeSession: boolean
    focusOnClick: boolean
    clipViewport: boolean
    dragViewport: boolean
    background: string
    _fbWidth?: number
    _fbHeight?: number
    _sock?: RFBInternalSocket
    disconnect(): void
    sendCredentials(creds: Record<string, unknown>): void
    sendKey(keysym: number, code: string | null, down?: boolean): void
    sendCtrlAltDel(): void
    focus(): void
    blur(): void
    machineShutdown(): void
    machineReboot(): void
    machineReset(): void
    clipboardPaste(text: string): void
    addEventListener(type: RFBEventType, listener: (e: RFBEvent) => void): void
    removeEventListener(type: RFBEventType, listener: (e: RFBEvent) => void): void
  }

  export default RFB
}
