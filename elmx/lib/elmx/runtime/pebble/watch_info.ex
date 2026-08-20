defmodule Elmx.Runtime.Pebble.WatchInfo do
  @moduledoc false

  alias Elmx.Runtime.Pebble.Colors
  alias Elmx.Types

  # Mirrors `Pebble.WatchInfo.caseColor` in elm-watch.
  @case_palette %{
    "UnknownColor" => "black",
    "Black" => "black",
    "White" => "white",
    "Red" => "red",
    "Orange" => "orange",
    "Gray" => "lightGray",
    "StainlessSteel" => "lightGray",
    "MatteBlack" => "black",
    "Blue" => "blue",
    "Green" => "green",
    "Pink" => "brilliantRose",
    "TimeWhite" => "white",
    "TimeBlack" => "black",
    "TimeRed" => "red",
    "TimeSteelSilver" => "lightGray",
    "TimeSteelBlack" => "black",
    "TimeSteelGold" => "brass",
    "TimeRoundSilver14" => "lightGray",
    "TimeRoundBlack14" => "black",
    "TimeRoundSilver20" => "lightGray",
    "TimeRoundBlack20" => "black",
    "TimeRoundRoseGold14" => "rajah",
    "Pebble2HrBlack" => "black",
    "Pebble2HrLime" => "springBud",
    "Pebble2HrFlame" => "sunsetOrange",
    "Pebble2HrWhite" => "white",
    "Pebble2HrAqua" => "tiffanyBlue",
    "Pebble2SeBlack" => "black",
    "Pebble2SeWhite" => "white",
    "PebbleTime2Black" => "black",
    "PebbleTime2Silver" => "lightGray",
    "PebbleTime2Gold" => "brass",
    "CoreDevicesP2DBlack" => "black",
    "CoreDevicesP2DWhite" => "white",
    "CoreDevicesPT2BlackGrey" => "black",
    "CoreDevicesPT2BlackRed" => "darkCandyAppleRed",
    "CoreDevicesPT2SilverBlue" => "cadetBlue",
    "CoreDevicesPT2SilverGrey" => "lightGray",
    "CoreDevicesPR2Black20" => "black",
    "CoreDevicesPR2Silver20" => "lightGray",
    "CoreDevicesPR2Gold14" => "brass",
    "CoreDevicesPR2Silver14" => "lightGray"
  }

  @spec case_color(Types.elm_value()) :: integer()
  def case_color(color), do: Colors.named(palette_name(color))

  @spec palette_name(Types.elm_value()) :: String.t()
  defp palette_name(color) when is_atom(color), do: palette_name(Atom.to_string(color))

  defp palette_name(%{"ctor" => ctor}) when is_binary(ctor), do: palette_name(ctor)

  defp palette_name(%{ctor: ctor}) when is_atom(ctor), do: palette_name(Atom.to_string(ctor))

  defp palette_name(%{ctor: ctor}) when is_binary(ctor), do: palette_name(ctor)

  defp palette_name(name) when is_binary(name) do
    Map.get(@case_palette, name, "black")
  end

  defp palette_name(_), do: "black"
end
