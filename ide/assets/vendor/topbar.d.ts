declare const topbar: {
  config: (opts: Record<string, unknown>) => void
  show: (delay?: number) => void
  hide: () => void
}

export default topbar
