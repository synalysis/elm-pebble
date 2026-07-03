defmodule Ide.Emulator.GColor8 do
  @moduledoc false

  alias Ide.Emulator.SdkScreenshotStyle

  @spec rgb_channels(non_neg_integer()) :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def rgb_channels(byte) when is_integer(byte) do
    alpha = Bitwise.band(Bitwise.bsr(byte, 6), 0x03)

    if alpha == 0 do
      {0, 0, 0}
    else
      red = Bitwise.band(Bitwise.bsr(byte, 4), 0x03)
      green = Bitwise.band(Bitwise.bsr(byte, 2), 0x03)
      blue = Bitwise.band(byte, 0x03)

      {channel_to_8bit(red), channel_to_8bit(green), channel_to_8bit(blue)}
    end
  end

  @spec display_rgb(non_neg_integer()) :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def display_rgb(byte) when is_integer(byte) do
    byte |> rgb_channels() |> SdkScreenshotStyle.correct_rgb_tuple()
  end

  @spec channel_to_8bit(non_neg_integer()) :: non_neg_integer()
  defp channel_to_8bit(value), do: max(0, min(3, value)) * 85
end
