defmodule Ide.Handheld.Models do
  @moduledoc """
  Handheld types for MeowKit and Flipper. This catalog is separate from
  `Ide.WatchModels`, so existing Pebble projects keep their watch platforms.
  """

  @ordered_ids ~w(meowkit flipper-zero)

  @profiles %{
    "meowkit" => %{
      "name" => "MeowKit",
      "shape" => "rect",
      "screen" => %{"width" => 320, "height" => 240},
      "color_depth" => 16,
      "color_mode" => "Color",
      "pack" => "meowkit",
      "has_touch" => true,
      "modules" => %{
        "nfc" => true,
        "ir" => true,
        "gpio" => true,
        "usb" => true,
        "radio" => true,
        "sensors" => true
      },
      "help" => "SD card package. 320×240 color. USB HID is present."
    },
    "flipper-zero" => %{
      "name" => "Flipper Zero",
      "shape" => "rect",
      "screen" => %{"width" => 128, "height" => 64},
      "color_depth" => 1,
      "color_mode" => "BlackWhite",
      "pack" => "flipper",
      "has_touch" => false,
      "modules" => %{
        "nfc" => true,
        "ir" => true,
        "gpio" => true,
        "usb" => false,
        "radio" => true,
        "sensors" => true
      },
      "help" => "Normal FAP. 128×64 mono. USB HID is absent."
    }
  }

  @spec ordered_ids() :: [String.t()]
  def ordered_ids, do: @ordered_ids

  @spec default_id() :: String.t()
  def default_id, do: "meowkit"

  @spec profiles_map() :: %{String.t() => map()}
  def profiles_map, do: @profiles

  @doc """
  True when this device has an in-IDE emulator page. New devices set
  `"emulator" => true` on their profile.
  """
  @spec emulator?(String.t() | nil) :: boolean()
  def emulator?(id), do: profile(id)["emulator"] == true

  @spec known?(String.t() | nil) :: boolean()
  def known?(id) when is_binary(id) do
    Map.has_key?(@profiles, normalize_key(id))
  end

  def known?(_), do: false

  @spec profile(String.t() | nil) :: map()
  def profile(id) when is_binary(id) do
    Map.get(@profiles, normalize_key(id), Map.fetch!(@profiles, default_id()))
  end

  def profile(_), do: Map.fetch!(@profiles, default_id())

  @spec normalize(String.t() | nil) :: String.t()
  def normalize(id) when is_binary(id) do
    key = normalize_key(id)
    if Map.has_key?(@profiles, key), do: key, else: default_id()
  end

  def normalize(_), do: default_id()

  @spec pack_target(String.t() | nil) :: :meowkit | :flipper
  def pack_target(id) do
    case profile(id)["pack"] do
      "flipper" -> :flipper
      _ -> :meowkit
    end
  end

  @doc """
  Pixel size for the IDE frame.
  """
  @spec preview_screen(String.t() | nil) :: {pos_integer(), pos_integer(), boolean()}
  def preview_screen(id) do
    screen = profile(id)["screen"]
    width = Map.get(screen, "width", 0)
    height = Map.get(screen, "height", 0)

    if is_integer(width) and is_integer(height) and width > 0 and height > 0 do
      {width, height, false}
    else
      {128, 64, true}
    end
  end

  @spec list_items() :: [map()]
  def list_items do
    Enum.map(@ordered_ids, fn id ->
      profile = Map.fetch!(@profiles, id)

      profile
      |> Map.put("id", id)
      |> Map.put("label", label(profile))
    end)
  end

  @spec platform_options() :: [map()]
  def platform_options do
    Enum.map(@ordered_ids, fn id ->
      profile = Map.fetch!(@profiles, id)
      %{id: id, label: profile["name"], help: profile["help"]}
    end)
  end

  @doc """
  Shape `Ide.Debugger` launch context already reads from a watch profile.
  """
  @spec watch_shaped_profile(String.t()) :: map()
  def watch_shaped_profile(id) when is_binary(id) do
    profile = profile(id)

    %{
      "name" => profile["name"],
      "shape" => profile["shape"],
      "screen" => profile["screen"],
      "color_mode" => profile["color_mode"],
      "has_microphone" => false,
      "has_compass" => false,
      "has_speaker" => false,
      "has_touch" => profile["has_touch"] == true,
      "supports_health" => false,
      "watch_info_model" => profile["name"],
      "watch_info_color" => "UnknownColor"
    }
  end

  @spec present_modules(String.t() | nil) :: [String.t()]
  def present_modules(id) do
    id
    |> profile()
    |> Map.get("modules", %{})
    |> Enum.filter(fn {_name, present} -> present == true end)
    |> Enum.map(fn {name, _} -> name end)
    |> Enum.sort()
  end

  defp label(profile) do
    screen = profile["screen"]
    width = screen["width"]
    height = screen["height"]
    depth = if profile["color_depth"] == 1, do: "mono", else: "color"

    size =
      if width == 0 or height == 0 do
        "panel unpublished"
      else
        "#{width}×#{height} #{depth}"
      end

    "#{profile["name"]} · #{size}"
  end

  defp normalize_key(id), do: id |> String.trim() |> String.downcase()
end
