defmodule Elmx.Runtime.LaunchContext do
  @moduledoc """
  Normalizes debugger wire launch metadata into the shape Elm `Platform` code expects.
  """

  alias Elmx.Types

  @launch_reason_int %{
    "LaunchSystem" => 0,
    "LaunchUser" => 1,
    "LaunchPhone" => 2,
    "LaunchWakeup" => 3,
    "LaunchWorker" => 4,
    "LaunchQuickLaunch" => 5,
    "LaunchTimelineAction" => 6,
    "LaunchSmartstrap" => 7,
    "LaunchUnknown" => -1
  }

  @spec normalize(Types.wire_map() | map()) :: Types.launch_context()
  def normalize(context) when is_map(context) do
    reason =
      case map_value(context, :reason) do
        %{"ctor" => _} = value -> value
        %{ctor: _} = value -> value
        value when is_binary(value) -> %{"ctor" => value, "args" => []}
        _ -> launch_reason_ctor(map_value(context, :launch_reason))
      end

    screen =
      case map_value(context, :screen) do
        value when is_map(value) -> launch_screen(value, context)
        _ -> launch_screen(%{}, context)
      end

    context
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put("reason", reason)
    |> Map.put("screen", screen)
    |> Map.put(
      "watchModel",
      map_value(context, :watch_model) || map_value(context, :watchModel) || "Basalt"
    )
    |> Map.put(
      "watchProfileId",
      map_value(context, :watch_profile_id) || map_value(context, :watchProfileId) || "basalt"
    )
    |> Map.put(
      "hasMicrophone",
      map_value(context, :has_microphone) || map_value(context, :hasMicrophone) || false
    )
    |> Map.put(
      "hasCompass",
      map_value(context, :has_compass) || map_value(context, :hasCompass) || false
    )
    |> Map.put(
      "supportsHealth",
      map_value(context, :supports_health) || map_value(context, :supportsHealth) || false
    )
  end

  def normalize(_), do: normalize(%{})

  @spec launch_reason_to_int(Types.launch_reason_like()) :: integer()
  def launch_reason_to_int(reason) do
    Map.get(@launch_reason_int, launch_reason_ctor_name(reason), -1)
  end

  @spec launch_reason_ctor(Types.launch_reason_like()) :: Types.wire_ctor()
  defp launch_reason_ctor(name) when is_binary(name) and name != "" do
    %{"ctor" => name, "args" => []}
  end

  defp launch_reason_ctor(_), do: %{"ctor" => "LaunchUser", "args" => []}

  @spec launch_reason_ctor_name(Types.launch_reason_like()) :: String.t()
  defp launch_reason_ctor_name(%{"ctor" => ctor, "args" => _}) when is_binary(ctor), do: ctor
  defp launch_reason_ctor_name(%{ctor: ctor, args: _}) when is_atom(ctor), do: Atom.to_string(ctor)
  defp launch_reason_ctor_name({ctor, _args}) when is_atom(ctor), do: Atom.to_string(ctor)
  defp launch_reason_ctor_name(name) when is_binary(name), do: name
  defp launch_reason_ctor_name(_), do: "LaunchUnknown"

  defp launch_screen(screen, context) when is_map(screen) and is_map(context) do
    shape_name = map_value(screen, :shape) || map_value(context, :shape) || "Rectangular"
    color_name = map_value(screen, :color_mode) || map_value(context, :color_mode) || "Color"

    is_round = display_shape_is_round?(shape_name)
    is_color = color_capability_is_color?(color_name)

    %{
      "width" => map_value(screen, :width) || 144,
      "height" => map_value(screen, :height) || 168,
      "shape" => display_shape_ctor(shape_name),
      "color_mode" => color_name,
      "colorMode" => color_mode_ctor(color_name),
      "is_color" => is_color,
      "is_round" => is_round
    }
  end

  defp display_shape_is_round?(shape) when is_binary(shape),
    do: String.contains?(String.downcase(shape), "round")

  defp display_shape_is_round?(_), do: false

  defp color_capability_is_color?("BlackWhite"), do: false
  defp color_capability_is_color?(%{"ctor" => "BlackWhite"}), do: false
  defp color_capability_is_color?({:BlackWhite}), do: false
  defp color_capability_is_color?(_), do: true

  defp display_shape_ctor(shape) when is_binary(shape) do
    if String.contains?(String.downcase(shape), "round") do
      %{"ctor" => "Round", "args" => []}
    else
      %{"ctor" => "Rectangular", "args" => []}
    end
  end

  defp display_shape_ctor(_), do: %{"ctor" => "Rectangular", "args" => []}

  defp color_mode_ctor("BlackWhite"), do: %{"ctor" => "BlackWhite", "args" => []}
  defp color_mode_ctor(_), do: %{"ctor" => "Color", "args" => []}

  defp map_value(map, key) when is_map(map) and (is_atom(key) or is_binary(key)) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end
end
