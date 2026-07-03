/** Pebble SDK screenshot palette remap (`pebble_tool.commands.screenshot._correct_colours/1`). */

const LEVELS = [0, 85, 170, 255] as const

export const PEBBLE_VNC_COLOUR_LOOKUP = new Uint8Array([
  0, 0, 0, 0, 30, 65, 0, 67, 135, 0, 104, 202, 43, 74, 44, 39, 81, 79, 22, 99, 141, 0, 125, 206,
  94, 152, 96, 92, 155, 114, 87, 165, 162, 76, 180, 219, 142, 227, 145, 142, 230, 158, 138, 235, 192,
  132, 245, 241, 74, 22, 27, 72, 39, 72, 64, 72, 138, 47, 107, 204, 86, 78, 54, 84, 84, 84, 79, 103,
  144, 65, 128, 208, 117, 154, 100, 117, 157, 118, 113, 166, 164, 105, 181, 221, 158, 229, 148, 157,
  231, 160, 155, 236, 194, 149, 246, 242, 153, 53, 63, 152, 62, 90, 149, 86, 148, 143, 116, 210, 157,
  91, 77, 157, 96, 100, 154, 112, 153, 149, 135, 213, 175, 160, 114, 174, 163, 130, 171, 171, 171,
  167, 186, 226, 201, 232, 157, 201, 234, 167, 199, 240, 200, 195, 249, 247, 227, 84, 98, 226, 88,
  116, 225, 106, 163, 222, 131, 220, 230, 110, 107, 230, 114, 124, 227, 127, 167, 225, 148, 223, 241,
  170, 134, 241, 173, 147, 239, 181, 184, 236, 195, 235, 255, 238, 171, 255, 241, 181, 255, 246, 211,
  255, 255, 255
])

const MONOCHROME_PLATFORMS = new Set(["aplite", "diorite"])

function levelIndex(channel: number): number {
  let best = 0
  let bestDelta = Math.abs(LEVELS[0]! - channel)
  for (let i = 1; i < LEVELS.length; i += 1) {
    const level = LEVELS[i]!
    const delta = Math.abs(level - channel)
    if (delta < bestDelta) {
      best = i
      bestDelta = delta
    }
  }
  return best
}

function lookupIndex(r: number, g: number, b: number): number {
  return levelIndex(r) * 16 + levelIndex(g) * 4 + levelIndex(b)
}

export function platformNeedsVncColourCorrection(platform: string | null | undefined): boolean {
  if (!platform) return true
  return !MONOCHROME_PLATFORMS.has(platform)
}

/** Remap QEMU/VNC truecolor pixels to Pebble display colours on a 2D canvas. */
export function correctVncCanvasColours(canvas: HTMLCanvasElement): boolean {
  const width = canvas.width
  const height = canvas.height
  if (width <= 0 || height <= 0) return false

  const context = canvas.getContext("2d", {willReadFrequently: true})
  if (!context) return false

  const image = context.getImageData(0, 0, width, height)
  const data = image.data
  const lookup = PEBBLE_VNC_COLOUR_LOOKUP

  for (let offset = 0; offset < data.length; offset += 4) {
    const alpha = data[offset + 3]
    if (alpha === 0) continue

    const index = lookupIndex(data[offset]!, data[offset + 1]!, data[offset + 2]!) * 3
    data[offset] = lookup[index]!
    data[offset + 1] = lookup[index + 1]!
    data[offset + 2] = lookup[index + 2]!
  }

  context.putImageData(image, 0, 0)
  return true
}
