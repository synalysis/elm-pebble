defmodule Ide.Emulator.PebblePalette do
  @moduledoc false

  @levels [0, 85, 170, 255]

  @doc """
  Snaps each RGB channel to Pebble's 2-bit-per-channel palette (multiples of 85).

  Firmware screenshots already use these values; VNC truecolor captures do not.
  """
  @spec quantize_rgb(binary()) :: binary()
  def quantize_rgb(rgb) when is_binary(rgb) do
    for <<r, g, b <- rgb>>, into: <<>> do
      <<quantize_channel(r), quantize_channel(g), quantize_channel(b)>>
    end
  end

  defp quantize_channel(value) do
    Enum.min_by(@levels, fn level -> abs(level - value) end)
  end
end
