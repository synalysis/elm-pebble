defmodule Ide.WatchModels do
  @moduledoc """
  Canonical watch model catalog used across debugger and emulator flows.

  Capability fields mirror Pebble SDK compile-time defines (`PBL_RECT`, `PBL_ROUND`,
  `PBL_COLOR`, `PBL_BW`, `PBL_MICROPHONE`, `PBL_COMPASS`, `PBL_HEALTH`).

  Typed shapes live in `Ide.WatchModels.Profile`; emulator APIs use
  `Ide.Emulator.Types` for session and screenshot contracts.
  """

  alias Ide.WatchModels.Profile

  @type screen :: Profile.screen()
  @type wire_screen :: Profile.wire_screen()
  @type profile :: Profile.t()
  @type wire_profile :: Profile.wire()
  @type profiles_map :: %{String.t() => wire_profile()}

  @ordered_ids ~w(aplite basalt chalk diorite emery flint gabbro)

  @profiles %{
    "aplite" => %{
      "name" => "Aplite",
      "shape" => "rect",
      "screen" => %{"width" => 144, "height" => 168},
      "color_mode" => "BlackWhite",
      "has_microphone" => false,
      "has_compass" => true,
      "supports_health" => false,
      "watch_info_model" => "PebbleOriginal",
      "watch_info_color" => "Black"
    },
    "basalt" => %{
      "name" => "Basalt",
      "shape" => "rect",
      "screen" => %{"width" => 144, "height" => 168},
      "color_mode" => "Color",
      "has_microphone" => false,
      "has_compass" => false,
      "supports_health" => true,
      "watch_info_model" => "PebbleTime",
      "watch_info_color" => "TimeBlack"
    },
    "chalk" => %{
      "name" => "Chalk",
      "shape" => "round",
      "screen" => %{"width" => 180, "height" => 180},
      "color_mode" => "Color",
      "has_microphone" => false,
      "has_compass" => false,
      "supports_health" => true,
      "watch_info_model" => "PebbleTimeRound20",
      "watch_info_color" => "TimeBlack"
    },
    "diorite" => %{
      "name" => "Diorite",
      "shape" => "rect",
      "screen" => %{"width" => 144, "height" => 168},
      "color_mode" => "BlackWhite",
      "has_microphone" => true,
      "has_compass" => false,
      "supports_health" => true,
      "watch_info_model" => "Pebble2Se",
      "watch_info_color" => "Black"
    },
    "emery" => %{
      "name" => "Emery",
      "shape" => "rect",
      "screen" => %{"width" => 200, "height" => 228},
      "color_mode" => "Color",
      "has_microphone" => true,
      "has_compass" => false,
      "supports_health" => true,
      "watch_info_model" => "PebbleTime2",
      "watch_info_color" => "TimeBlack"
    },
    "flint" => %{
      "name" => "Flint",
      "shape" => "rect",
      "screen" => %{"width" => 144, "height" => 168},
      "color_mode" => "Color",
      "has_microphone" => true,
      "has_compass" => false,
      "supports_health" => true,
      "watch_info_model" => "Pebble2Hr",
      "watch_info_color" => "TimeBlack"
    },
    "gabbro" => %{
      "name" => "Gabbro",
      "shape" => "round",
      "screen" => %{"width" => 180, "height" => 180},
      "color_mode" => "Color",
      "has_microphone" => false,
      "has_compass" => false,
      "supports_health" => true,
      "watch_info_model" => "PebbleTimeRound20",
      "watch_info_color" => "TimeBlack"
    }
  }

  @spec ordered_ids() :: [String.t()]
  def ordered_ids, do: @ordered_ids

  @spec default_id() :: String.t()
  def default_id, do: "basalt"

  @spec profiles_map() :: profiles_map()
  def profiles_map, do: @profiles

  @spec watch_info_model_ctor(String.t() | nil) :: String.t()
  def watch_info_model_ctor(id) do
    id
    |> profile_for()
    |> Map.get("watch_info_model", "UnknownModel")
  end

  @spec watch_info_color_ctor(String.t() | nil) :: String.t()
  def watch_info_color_ctor(id) do
    id
    |> profile_for()
    |> Map.get("watch_info_color", "UnknownColor")
  end

  @spec watch_info_model_ctor_from_launch_context(map()) :: String.t()
  def watch_info_model_ctor_from_launch_context(launch_context) when is_map(launch_context) do
    profile_id =
      Map.get(launch_context, "watch_profile_id") ||
        Map.get(launch_context, :watch_profile_id) ||
        default_id()

    watch_info_model_ctor(profile_id)
  end

  @spec watch_info_color_ctor_from_launch_context(map()) :: String.t()
  def watch_info_color_ctor_from_launch_context(launch_context) when is_map(launch_context) do
    profile_id =
      Map.get(launch_context, "watch_profile_id") ||
        Map.get(launch_context, :watch_profile_id) ||
        default_id()

    watch_info_color_ctor(profile_id)
  end

  @spec profile_for(String.t() | nil) :: wire_profile()
  def profile_for(id) when is_binary(id) do
    normalized = String.downcase(String.trim(id))
    Map.get(@profiles, normalized, Map.fetch!(@profiles, default_id()))
  end

  def profile_for(_), do: Map.fetch!(@profiles, default_id())

  @doc """
  Screen dimensions from a catalog profile (string-key `"screen"` map).
  """
  @spec profile_screen(wire_profile()) :: wire_screen()
  def profile_screen(%{"screen" => %{} = screen}), do: screen
  def profile_screen(%{screen: %{} = screen}), do: screen

  def profile_screen(_profile) do
    default = Map.fetch!(@profiles, default_id())
    Map.fetch!(default, "screen")
  end
end
