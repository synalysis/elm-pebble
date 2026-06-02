defmodule Ide.Resources.PebbleColor do
  @moduledoc """
  Parses SVG color values and converts them to Pebble ARGB8 draw-command bytes.

  Supports `#RRGGBB` / `#RGB` hex, standard CSS color keywords, and Pebble
  `Pebble.Ui.Color` names such as `vividCerulean` and `blueMoon`.
  """

  @type argb8 :: 0..255

  @named_colors %{
    "clearcolor" => 0x00,
    "black" => 0xC0,
    "oxfordblue" => 0xC1,
    "dukeblue" => 0xC2,
    "blue" => 0xC3,
    "darkgreen" => 0xC4,
    "midnightgreen" => 0xC5,
    "cobaltblue" => 0xC6,
    "bluemoon" => 0xC7,
    "islamicgreen" => 0xC8,
    "jaegergreen" => 0xC9,
    "tiffanyblue" => 0xCA,
    "vividcerulean" => 0xCB,
    "green" => 0xCC,
    "malachite" => 0xCD,
    "mediumspringgreen" => 0xCE,
    "cyan" => 0xCF,
    "bulgarianrose" => 0xD0,
    "imperialpurple" => 0xD1,
    "indigo" => 0xD2,
    "electricultramarine" => 0xD3,
    "armygreen" => 0xD4,
    "darkgray" => 0xD5,
    "liberty" => 0xD6,
    "verylightblue" => 0xD7,
    "kellygreen" => 0xD8,
    "maygreen" => 0xD9,
    "cadetblue" => 0xDA,
    "pictonblue" => 0xDB,
    "brightgreen" => 0xDC,
    "screamingreen" => 0xDD,
    "mediumaquamarine" => 0xDE,
    "electricblue" => 0xDF,
    "darkcandyapplered" => 0xE0,
    "jazzberryjam" => 0xE1,
    "purple" => 0xE2,
    "vividviolet" => 0xE3,
    "windsortan" => 0xE4,
    "rosevale" => 0xE5,
    "purpureus" => 0xE6,
    "lavenderindigo" => 0xE7,
    "limerick" => 0xE8,
    "brass" => 0xE9,
    "lightgray" => 0xEA,
    "babyblueeyes" => 0xEB,
    "springbud" => 0xEC,
    "inchworm" => 0xED,
    "mintgreen" => 0xEE,
    "celeste" => 0xEF,
    "red" => 0xF0,
    "folly" => 0xF1,
    "fashionmagenta" => 0xF2,
    "magenta" => 0xF3,
    "orange" => 0xF4,
    "sunsetorange" => 0xF5,
    "brilliantrose" => 0xF6,
    "shockingpink" => 0xF7,
    "chromeyellow" => 0xF8,
    "rajah" => 0xF9,
    "melon" => 0xFA,
    "richbrilliantlavender" => 0xFB,
    "yellow" => 0xFC,
    "icterine" => 0xFD,
    "pastelyellow" => 0xFE,
    "white" => 0xFF,
    "transparent" => 0x00,
    "none" => 0x00
  }

  @spec parse(String.t() | nil, float(), keyword()) :: argb8()
  def parse(color, opacity, opts \\ [])
  def parse(nil, _opacity, _opts), do: 0
  def parse("", _opacity, _opts), do: 0

  def parse(color, opacity, opts) when is_binary(color) do
    color = String.trim(color)
    color_mode = Keyword.get(opts, :color_mode, :truncate)

    cond do
      color in ["none", "transparent"] ->
        0

      color == "currentColor" ->
        0

      String.starts_with?(color, "#") ->
        color
        |> parse_hex()
        |> apply_hex_opacity(opacity, color_mode)

      String.match?(color, ~r/^rgba?\s*\(/i) ->
        color
        |> parse_rgb_function()
        |> rgba_to_argb8(opacity, color_mode)

      true ->
        case Map.get(@named_colors, normalize_name(color)) do
          nil ->
            0

          argb8 when is_integer(argb8) ->
            if opacity <= 0.0, do: 0, else: argb8
        end
    end
  end

  defp apply_hex_opacity({r, g, b, a}, opacity, color_mode),
    do: rgba_to_argb8({r, g, b}, opacity * a / 255.0, color_mode)

  defp apply_hex_opacity({r, g, b}, opacity, color_mode),
    do: rgba_to_argb8({r, g, b}, opacity, color_mode)

  @spec rgba_to_argb8(
          {non_neg_integer(), non_neg_integer(), non_neg_integer()},
          number(),
          :truncate | :nearest
        ) :: argb8()
  def rgba_to_argb8({r, g, b}, opacity, color_mode \\ :truncate)
      when is_float(opacity) or is_integer(opacity) do
    a = opacity_to_alpha(opacity)

    {r, g, b, a}
    |> quantize_to_palette(color_mode)
    |> triplet_to_argb8()
  end

  @spec triplet_to_argb8(
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
        ) ::
          argb8()
  def triplet_to_argb8({r, g, b, a}) do
    a = Bitwise.bsr(a, 6)
    r = Bitwise.bsr(r, 6)
    g = Bitwise.bsr(g, 6)
    b = Bitwise.bsr(b, 6)

    Bitwise.bor(
      Bitwise.bor(Bitwise.bsl(a, 6), Bitwise.bsl(r, 4)),
      Bitwise.bor(Bitwise.bsl(g, 2), b)
    )
    |> band_argb8()
  end

  @spec band_argb8(non_neg_integer()) :: argb8()
  defp band_argb8(value), do: Bitwise.band(value, 0xFF)

  @spec truncate_to_palette(
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
        ) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def truncate_to_palette({r, g, b, a}) do
    a = div(a, 85) * 85

    if a == 0 do
      {0, 0, 0, 0}
    else
      {div(r, 85) * 85, div(g, 85) * 85, div(b, 85) * 85, a}
    end
  end

  @spec nearest_to_palette(
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
        ) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def nearest_to_palette({r, g, b, a}) do
    a = nearest_step(a)

    if a == 0 do
      {0, 0, 0, 0}
    else
      {nearest_step(r), nearest_step(g), nearest_step(b), a}
    end
  end

  defp quantize_to_palette(rgba, :nearest), do: nearest_to_palette(rgba)
  defp quantize_to_palette(rgba, _), do: truncate_to_palette(rgba)

  defp nearest_step(value) when is_integer(value) do
    (((value + 42) / 85) |> trunc()) * 85
  end

  defp parse_hex("#" <> hex) do
    hex = String.downcase(hex)

    case byte_size(hex) do
      3 ->
        <<r, g, b>> = hex
        {dehex(r) * 17, dehex(g) * 17, dehex(b) * 17}

      6 ->
        <<r1, r2, g1, g2, b1, b2>> = hex
        {dehex(r1) * 16 + dehex(r2), dehex(g1) * 16 + dehex(g2), dehex(b1) * 16 + dehex(b2)}

      8 ->
        <<r1, r2, g1, g2, b1, b2, a1, a2>> = hex

        {
          dehex(r1) * 16 + dehex(r2),
          dehex(g1) * 16 + dehex(g2),
          dehex(b1) * 16 + dehex(b2),
          dehex(a1) * 16 + dehex(a2)
        }

      _ ->
        {0, 0, 0}
    end
  end

  defp parse_hex(_), do: {0, 0, 0}

  defp parse_rgb_function(color) do
    case Regex.run(~r/rgba?\(\s*([^)]+)\)/i, color) do
      [_, body] ->
        parts =
          body
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&parse_number/1)

        case parts do
          [r, g, b] -> {r, g, b}
          [r, g, b, _a] -> {r, g, b}
          _ -> {0, 0, 0}
        end

      _ ->
        {0, 0, 0}
    end
  end

  defp parse_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> trunc(number)
      :error -> 0
    end
  end

  defp opacity_to_alpha(opacity) when is_integer(opacity), do: opacity_to_alpha(opacity * 1.0)

  defp opacity_to_alpha(opacity) when is_float(opacity) do
    opacity
    |> max(0.0)
    |> min(1.0)
    |> Kernel.*(255)
    |> round()
  end

  defp normalize_name(name) do
    name
    |> String.trim()
    |> String.replace(~r/[\s_-]+/, "")
    |> String.downcase()
  end

  defp dehex(?0), do: 0
  defp dehex(?1), do: 1
  defp dehex(?2), do: 2
  defp dehex(?3), do: 3
  defp dehex(?4), do: 4
  defp dehex(?5), do: 5
  defp dehex(?6), do: 6
  defp dehex(?7), do: 7
  defp dehex(?8), do: 8
  defp dehex(?9), do: 9
  defp dehex(?a), do: 10
  defp dehex(?b), do: 11
  defp dehex(?c), do: 12
  defp dehex(?d), do: 13
  defp dehex(?e), do: 14
  defp dehex(?f), do: 15
  defp dehex(?A), do: 10
  defp dehex(?B), do: 11
  defp dehex(?C), do: 12
  defp dehex(?D), do: 13
  defp dehex(?E), do: 14
  defp dehex(?F), do: 15
  defp dehex(_), do: 0
end
