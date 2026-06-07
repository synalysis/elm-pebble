export type ScreenSize = {
  width: number
  height: number
}

export type DisplayShape = "round" | "rect"

export type VncViewportOffset = {
  x: number
  y: number
}

export type VncViewportMode = "clip" | "scale"

const ROUND_SCALE_PADDING_THRESHOLD = 8

/** Round QEMU surfaces (Gabbro) often expose a much larger VNC buffer than the logical screen. */
export function shouldScaleRoundFramebuffer(framebuffer: ScreenSize, screen: ScreenSize): boolean {
  return (
    framebuffer.width - screen.width > ROUND_SCALE_PADDING_THRESHOLD ||
    framebuffer.height - screen.height > ROUND_SCALE_PADDING_THRESHOLD
  )
}

export function vncViewportMode(
  framebuffer: ScreenSize,
  screen: ScreenSize,
  shape: DisplayShape
): VncViewportMode {
  if (shape === "round" && shouldScaleRoundFramebuffer(framebuffer, screen)) {
    return "scale"
  }

  return "clip"
}

/** Clip mode only: rectangular padding is right/bottom; round uses top-left when not scaling. */
export function computeVncViewportOffset(
  framebuffer: ScreenSize,
  screen: ScreenSize,
  shape: DisplayShape,
  mode: VncViewportMode
): VncViewportOffset {
  if (mode === "scale") {
    return {x: 0, y: 0}
  }

  const deltaW = framebuffer.width - screen.width
  const deltaH = framebuffer.height - screen.height

  if (deltaW <= 0 && deltaH <= 0) {
    return {x: 0, y: 0}
  }

  // Round watches without heavy padding (Chalk) still use the origin-aligned panel.
  if (shape === "round") {
    return {x: 0, y: 0}
  }

  // Rectangular surfaces keep the app framebuffer at the origin; padding is on
  // the right/bottom (scanline stride), matching screenshot crop_framebuffer/0.
  return {x: 0, y: 0}
}

export function vncViewportConfigKey(
  framebuffer: ScreenSize,
  screen: ScreenSize,
  mode: VncViewportMode,
  offset: VncViewportOffset
): string {
  return `${framebuffer.width}x${framebuffer.height}:${screen.width}x${screen.height}:${mode}:${offset.x},${offset.y}`
}
