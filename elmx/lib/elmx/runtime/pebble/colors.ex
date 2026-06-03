defmodule Elmx.Runtime.Pebble.Colors do
  @moduledoc """
  Pebble `GColor` constants and `Color` ADT conversion for the elmx UI runtime.

  Values match `Elmc.Backend.CCodegen.Constants.pebble_color_constants/0`.
  """

  alias Elmx.Types

  import Bitwise

  @named_constants %{
    "clearColor" => 0x00,
    "black" => 0xC0,
    "oxfordBlue" => 0xC1,
    "dukeBlue" => 0xC2,
    "blue" => 0xC3,
    "darkGreen" => 0xC4,
    "midnightGreen" => 0xC5,
    "cobaltBlue" => 0xC6,
    "blueMoon" => 0xC7,
    "islamicGreen" => 0xC8,
    "jaegerGreen" => 0xC9,
    "tiffanyBlue" => 0xCA,
    "vividCerulean" => 0xCB,
    "green" => 0xCC,
    "malachite" => 0xCD,
    "mediumSpringGreen" => 0xCE,
    "cyan" => 0xCF,
    "bulgarianRose" => 0xD0,
    "imperialPurple" => 0xD1,
    "indigo" => 0xD2,
    "electricUltramarine" => 0xD3,
    "armyGreen" => 0xD4,
    "darkGray" => 0xD5,
    "liberty" => 0xD6,
    "veryLightBlue" => 0xD7,
    "kellyGreen" => 0xD8,
    "mayGreen" => 0xD9,
    "cadetBlue" => 0xDA,
    "pictonBlue" => 0xDB,
    "brightGreen" => 0xDC,
    "screaminGreen" => 0xDD,
    "mediumAquamarine" => 0xDE,
    "electricBlue" => 0xDF,
    "darkCandyAppleRed" => 0xE0,
    "jazzberryJam" => 0xE1,
    "purple" => 0xE2,
    "vividViolet" => 0xE3,
    "windsorTan" => 0xE4,
    "roseVale" => 0xE5,
    "purpureus" => 0xE6,
    "lavenderIndigo" => 0xE7,
    "limerick" => 0xE8,
    "brass" => 0xE9,
    "lightGray" => 0xEA,
    "babyBlueEyes" => 0xEB,
    "springBud" => 0xEC,
    "inchworm" => 0xED,
    "mintGreen" => 0xEE,
    "celeste" => 0xEF,
    "red" => 0xF0,
    "folly" => 0xF1,
    "fashionMagenta" => 0xF2,
    "magenta" => 0xF3,
    "orange" => 0xF4,
    "sunsetOrange" => 0xF5,
    "brilliantRose" => 0xF6,
    "shockingPink" => 0xF7,
    "chromeYellow" => 0xF8,
    "rajah" => 0xF9,
    "melon" => 0xFA,
    "richBrilliantLavender" => 0xFB,
    "yellow" => 0xFC,
    "icterine" => 0xFD,
    "pastelYellow" => 0xFE,
    "white" => 0xFF
  }

  @spec named(String.t()) :: integer()
  def named(name) when is_binary(name) do
    Map.get(@named_constants, name, @named_constants["black"])
  end

  @spec to_int(Types.ui_color()) :: integer()
  def to_int(color) when is_integer(color) and color >= 0 and color <= 0xFF, do: color

  def to_int(0xFFFFFFFF), do: @named_constants["white"]
  def to_int(0xFF000000), do: @named_constants["black"]

  def to_int(color) when is_integer(color) and color >= 0x100 do
    alpha = band(bsr(color, 24), 0xFF)

    pack_rgba8(
      band(bsr(color, 16), 0xFF),
      band(bsr(color, 8), 0xFF),
      band(color, 0xFF),
      alpha
    )
  end

  def to_int({:Indexed, code}), do: clamp_byte(code)
  def to_int({:RGBA, r, g, b, a}), do: pack_rgba8(r, g, b, a)

  def to_int(%{"ctor" => "Indexed", "args" => [code]}), do: clamp_byte(code)
  def to_int(%{ctor: :Indexed, args: [code]}), do: clamp_byte(code)

  def to_int(%{"ctor" => "RGBA", "args" => [r, g, b, a]}),
    do: pack_rgba8(r, g, b, a)

  def to_int(%{ctor: :RGBA, args: [r, g, b, a]}),
    do: pack_rgba8(r, g, b, a)

  def to_int(_), do: @named_constants["black"]

  @spec pack_rgba8(Types.ui_coord(), Types.ui_coord(), Types.ui_coord(), Types.ui_coord()) ::
          integer()
  defp pack_rgba8(r, g, b, a) do
    rr = channel_to_2bit(r)
    gg = channel_to_2bit(g)
    bb = channel_to_2bit(b)
    aa = channel_to_2bit(a)

    aa <<< 6 ||| rr <<< 4 ||| gg <<< 2 ||| bb
  end

  defp channel_to_2bit(value) when is_integer(value) and value <= 3, do: value
  defp channel_to_2bit(value) when is_integer(value), do: min(3, div(max(value, 0), 64))
  defp channel_to_2bit(_), do: 0

  defp clamp_byte(value) when is_integer(value), do: max(0, min(255, value))
  defp clamp_byte(_), do: 0
end
