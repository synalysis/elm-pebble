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

  @quick_launch_action_int %{
    "QuickLaunchNone" => 0,
    "QuickLaunchHold" => 1,
    "QuickLaunchTap" => 2,
    "QuickLaunchCombo" => 3,
    "QuickLaunchUnknown" => -1
  }

  @spec normalize(Types.wire_map()) :: Types.launch_context()
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
    |> Map.put(
      "launchButton",
      launch_button_maybe(
        map_value(context, :launch_button) || map_value(context, :launchButton)
      )
    )
    |> Map.put(
      "quickLaunchAction",
      quick_launch_action_ctor(
        map_value(context, :quick_launch_action) || map_value(context, :quickLaunchAction)
      )
    )
    |> Map.put_new("configurationResponse", nil)
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

  @spec quick_launch_action_ctor(Types.quick_launch_action_like()) :: Types.wire_ctor()
  defp quick_launch_action_ctor(%{"ctor" => _} = value), do: value
  defp quick_launch_action_ctor(%{ctor: _} = value), do: value
  defp quick_launch_action_ctor({ctor, _args}) when is_atom(ctor), do: %{"ctor" => Atom.to_string(ctor), "args" => []}
  defp quick_launch_action_ctor(name) when is_binary(name) and name != "", do: %{"ctor" => name, "args" => []}
  defp quick_launch_action_ctor(tag) when is_integer(tag), do: quick_launch_action_ctor(quick_launch_action_name(tag))
  defp quick_launch_action_ctor(_), do: %{"ctor" => "QuickLaunchNone", "args" => []}

  @spec quick_launch_action_name(integer()) :: String.t()
  defp quick_launch_action_name(tag) do
    @quick_launch_action_int
    |> Enum.find_value("QuickLaunchUnknown", fn {name, int} -> if int == tag, do: name end)
  end

  @launch_buttons ~w(Back Up Select Down)

  @spec launch_button_maybe(Types.button_like()) :: Types.maybe_wire()
  defp launch_button_maybe(%{"ctor" => "Nothing"} = value), do: value
  defp launch_button_maybe(%{"ctor" => "Just", "args" => _} = value), do: value
  defp launch_button_maybe(%{ctor: :Nothing}), do: %{"ctor" => "Nothing", "args" => []}
  defp launch_button_maybe(%{ctor: :Just, args: [button]}), do: %{"ctor" => "Just", "args" => [button_ctor(button)]}
  defp launch_button_maybe({:Just, button}), do: %{"ctor" => "Just", "args" => [button_ctor(button)]}
  defp launch_button_maybe(:Nothing), do: %{"ctor" => "Nothing", "args" => []}
  defp launch_button_maybe(nil), do: %{"ctor" => "Nothing", "args" => []}
  defp launch_button_maybe(""), do: %{"ctor" => "Nothing", "args" => []}
  defp launch_button_maybe(button), do: %{"ctor" => "Just", "args" => [button_ctor(button)]}

  @spec button_ctor(Types.button_like()) :: Types.wire_ctor()
  defp button_ctor(%{"ctor" => _} = value), do: value
  defp button_ctor(%{ctor: ctor, args: args}) when is_binary(ctor), do: %{"ctor" => ctor, "args" => args || []}
  defp button_ctor({ctor, _args}) when is_atom(ctor), do: %{"ctor" => Atom.to_string(ctor), "args" => []}
  defp button_ctor(name) when is_binary(name) and name in @launch_buttons, do: %{"ctor" => name, "args" => []}
  defp button_ctor(_), do: %{"ctor" => "Select", "args" => []}

  defp launch_screen(screen, context) when is_map(screen) and is_map(context) do
    shape = launch_shape_value(screen, context)
    color = launch_color_value(screen, context)

    is_round = display_shape_is_round?(shape)
    is_color = color_capability_is_color?(color)

    %{
      "width" => map_value(screen, :width) || 144,
      "height" => map_value(screen, :height) || 168,
      "shape" => display_shape_ctor(shape),
      "color_mode" => color_mode_name(color),
      "colorMode" => color_mode_ctor(color),
      "is_color" => is_color,
      "is_round" => is_round
    }
  end

  defp launch_shape_value(screen, context) when is_map(screen) and is_map(context) do
    case map_value(screen, :shape) || map_value(context, :shape) do
      %{"ctor" => ctor, "args" => _} = value when is_binary(ctor) ->
        value

      %{ctor: ctor, args: args} when is_binary(ctor) ->
        %{"ctor" => ctor, "args" => args || []}

      {ctor, _} when is_atom(ctor) ->
        %{"ctor" => Atom.to_string(ctor), "args" => []}

      shape when is_binary(shape) ->
        shape

      _ ->
        "Rectangular"
    end
  end

  defp launch_color_value(screen, context) when is_map(screen) and is_map(context) do
    case map_value(screen, :color_mode) || map_value(context, :color_mode) do
      %{"ctor" => ctor, "args" => _} = value when is_binary(ctor) ->
        value

      %{ctor: ctor, args: args} when is_binary(ctor) ->
        %{"ctor" => ctor, "args" => args || []}

      {ctor, _} when is_atom(ctor) ->
        %{"ctor" => Atom.to_string(ctor), "args" => []}

      mode when is_binary(mode) ->
        mode

      _ ->
        "Color"
    end
  end

  defp display_shape_is_round?(%{"ctor" => ctor}) when is_binary(ctor),
    do: String.contains?(String.downcase(ctor), "round")

  defp display_shape_is_round?(%{ctor: ctor}) when is_binary(ctor) or is_atom(ctor),
    do: display_shape_is_round?(Atom.to_string(ctor))

  defp display_shape_is_round?(shape) when is_binary(shape),
    do: String.contains?(String.downcase(shape), "round")

  defp display_shape_is_round?(_), do: false

  defp color_capability_is_color?("BlackWhite"), do: false
  defp color_capability_is_color?(%{"ctor" => "BlackWhite"}), do: false
  defp color_capability_is_color?(%{ctor: "BlackWhite"}), do: false
  defp color_capability_is_color?(_), do: true

  defp color_mode_name("BlackWhite"), do: "BlackWhite"
  defp color_mode_name(%{"ctor" => ctor, "args" => _}) when is_binary(ctor), do: ctor
  defp color_mode_name(%{ctor: ctor, args: _}) when is_binary(ctor), do: ctor
  defp color_mode_name(mode) when is_binary(mode), do: mode
  defp color_mode_name(_), do: "Color"

  defp display_shape_ctor(%{"ctor" => ctor, "args" => args} = value) when is_binary(ctor) do
    Map.put(value, "args", args || [])
  end

  defp display_shape_ctor(%{ctor: ctor, args: args}) when is_binary(ctor) do
    %{"ctor" => ctor, "args" => args || []}
  end

  defp display_shape_ctor(shape) when is_binary(shape) do
    if String.contains?(String.downcase(shape), "round") do
      %{"ctor" => "Round", "args" => []}
    else
      %{"ctor" => "Rectangular", "args" => []}
    end
  end

  defp display_shape_ctor(_), do: %{"ctor" => "Rectangular", "args" => []}

  defp color_mode_ctor("BlackWhite"), do: %{"ctor" => "BlackWhite", "args" => []}
  defp color_mode_ctor(%{"ctor" => ctor, "args" => _} = value) when is_binary(ctor), do: value
  defp color_mode_ctor(%{ctor: ctor, args: args}) when is_binary(ctor), do: %{"ctor" => ctor, "args" => args || []}
  defp color_mode_ctor(_), do: %{"ctor" => "Color", "args" => []}

  defp map_value(map, key) when is_map(map) and (is_atom(key) or is_binary(key)) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end
end
