defmodule Ide.WatchModels do
  @moduledoc """
  Canonical watch model catalog used across debugger and emulator flows.

  Capability fields mirror Pebble SDK compile-time defines (`PBL_RECT`, `PBL_ROUND`,
  `PBL_COLOR`, `PBL_BW`, `PBL_MICROPHONE`, `PBL_COMPASS`, `PBL_HEALTH`).
  """

  @ordered_ids ~w(aplite basalt chalk diorite emery flint gabbro)

  @profiles %{
    "aplite" => %{
      "name" => "Aplite",
      "shape" => "rect",
      "screen" => %{"width" => 144, "height" => 168},
      "color_mode" => "BlackWhite",
      "has_microphone" => false,
      "has_compass" => true,
      "supports_health" => false
    },
    "basalt" => %{
      "name" => "Basalt",
      "shape" => "rect",
      "screen" => %{"width" => 144, "height" => 168},
      "color_mode" => "Color",
      "has_microphone" => false,
      "has_compass" => false,
      "supports_health" => true
    },
    "chalk" => %{
      "name" => "Chalk",
      "shape" => "round",
      "screen" => %{"width" => 180, "height" => 180},
      "color_mode" => "Color",
      "has_microphone" => false,
      "has_compass" => false,
      "supports_health" => true
    },
    "diorite" => %{
      "name" => "Diorite",
      "shape" => "rect",
      "screen" => %{"width" => 144, "height" => 168},
      "color_mode" => "BlackWhite",
      "has_microphone" => true,
      "has_compass" => false,
      "supports_health" => true
    },
    "emery" => %{
      "name" => "Emery",
      "shape" => "rect",
      "screen" => %{"width" => 200, "height" => 228},
      "color_mode" => "Color",
      "has_microphone" => true,
      "has_compass" => false,
      "supports_health" => true
    },
    "flint" => %{
      "name" => "Flint",
      "shape" => "rect",
      "screen" => %{"width" => 144, "height" => 168},
      "color_mode" => "Color",
      "has_microphone" => true,
      "has_compass" => false,
      "supports_health" => true
    },
    "gabbro" => %{
      "name" => "Gabbro",
      "shape" => "round",
      "screen" => %{"width" => 180, "height" => 180},
      "color_mode" => "Color",
      "has_microphone" => false,
      "has_compass" => false,
      "supports_health" => true
    }
  }

  @spec ordered_ids() :: [String.t()]
  def ordered_ids, do: @ordered_ids

  @spec default_id() :: String.t()
  def default_id, do: "basalt"

  @spec profiles_map() :: map()
  def profiles_map, do: @profiles

  @spec profile_for(String.t() | nil) :: map()
  def profile_for(id) when is_binary(id) do
    normalized = String.downcase(String.trim(id))
    Map.get(@profiles, normalized, Map.fetch!(@profiles, default_id()))
  end

  def profile_for(_), do: Map.fetch!(@profiles, default_id())
end
