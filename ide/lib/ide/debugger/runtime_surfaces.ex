defmodule Ide.Debugger.RuntimeSurfaces do
  @moduledoc false

  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.WatchModels

  @spec default_watch(Types.launch_context() | nil) :: Surface.surface_map()
  def default_watch(launch_context \\ nil)

  def default_watch(nil) do
    default_watch(launch_context_for(WatchModels.default_id(), "LaunchUser", %{}))
  end

  def default_watch(launch_context) when is_map(launch_context) do
    Surface.from_map(%{
      model: %{
        "status" => "idle",
        "launch_context" => launch_context
      },
      last_message: nil,
      protocol_messages: [],
      view_tree: %{"type" => "root", "children" => []}
    })
    |> Surface.to_map()
  end

  @spec default_companion() :: Surface.surface_map()
  def default_companion do
    Surface.from_map(%{
      model: protocol_model("idle"),
      last_message: nil,
      protocol_messages: [],
      view_tree: %{
        "type" => "CompanionRoot",
        "label" => "idle",
        "box" => %{"x" => 0, "y" => 0, "w" => 180, "h" => 320},
        "children" => []
      }
    })
    |> Surface.to_map()
  end

  @spec default_phone() :: Surface.surface_map()
  def default_phone do
    Surface.from_map(%{
      model: protocol_model("idle"),
      last_message: nil,
      protocol_messages: [],
      view_tree: %{
        "type" => "PhoneRoot",
        "label" => "idle",
        "box" => %{"x" => 0, "y" => 0, "w" => 200, "h" => 360},
        "children" => []
      }
    })
    |> Surface.to_map()
  end

  @spec protocol_model(String.t()) :: Types.app_model()
  def protocol_model(status) when is_binary(status) do
    %{
      "status" => status,
      "runtime_model" => %{
        "status" => status,
        "protocol_inbound_count" => 0,
        "protocol_message_count" => 0
      }
    }
  end

  @spec ensure_protocol_runtime_model(Types.runtime_state(), :companion | :phone) ::
          Types.runtime_state()
  def ensure_protocol_runtime_model(state, surface) when is_map(state) do
    Surface.update_in_state(state, surface, fn s ->
      model = Surface.app_model(s)
      runtime_model = Map.get(model, "runtime_model") || %{}
      runtime_model = if is_map(runtime_model), do: runtime_model, else: %{}
      protocol_messages = s.protocol_messages
      protocol_messages = if is_list(protocol_messages), do: protocol_messages, else: []
      status = Map.get(model, "status") || Map.get(runtime_model, "status") || "idle"

      inbound_count =
        Map.get(model, "protocol_inbound_count") ||
          Map.get(runtime_model, "protocol_inbound_count") || 0

      last_message =
        Map.get(model, "protocol_last_inbound_message") ||
          Map.get(runtime_model, "protocol_last_inbound_message")

      last_from =
        Map.get(model, "protocol_last_inbound_from") ||
          Map.get(runtime_model, "protocol_last_inbound_from")

      runtime_model =
        runtime_model
        |> Map.put_new("status", status)
        |> Map.put_new("protocol_inbound_count", inbound_count)
        |> Map.put("protocol_message_count", length(protocol_messages))
        |> maybe_put_runtime_value("protocol_last_inbound_message", last_message)
        |> maybe_put_runtime_value("protocol_last_inbound_from", last_from)

      Surface.put_app_model(s, Map.put(model, "runtime_model", runtime_model))
    end)
  end

  @spec apply_launch_context_to_watch(Types.runtime_state()) :: Types.runtime_state()
  def apply_launch_context_to_watch(state) when is_map(state) do
    launch_context = Map.get(state, :launch_context) || %{}

    Surface.update_in_state(state, :watch, fn watch ->
      model = merge_launch_context_model(Surface.app_model(watch), launch_context)
      view_tree = merge_launch_context_view_tree(watch.view_tree || %{}, launch_context)

      watch
      |> Surface.put_app_model(model)
      |> Surface.put_view_tree(view_tree)
    end)
  end

  @spec apply_launch_context(Types.runtime_state(), String.t()) :: Types.runtime_state()
  def apply_launch_context(state, launch_reason)
      when is_map(state) and is_binary(launch_reason) do
    watch_profile_id = parse_watch_profile_id(Map.get(state, :watch_profile_id))
    launch_reason = parse_launch_reason(launch_reason)

    settings =
      state
      |> Map.get(:simulator_settings, %{})
      |> Map.put("launch_reason", launch_reason)

    launch_context = launch_context_for(watch_profile_id, launch_reason, settings)

    state
    |> Map.put(:watch_profile_id, watch_profile_id)
    |> Map.put(:launch_context, launch_context)
    |> Surface.update_in_state(:watch, fn watch ->
      model = merge_launch_context_model(Surface.app_model(watch), launch_context)
      view_tree = merge_launch_context_view_tree(watch.view_tree || %{}, launch_context)

      watch
      |> Surface.put_app_model(model)
      |> Surface.put_view_tree(view_tree)
    end)
  end

  @spec launch_context_for(String.t(), String.t()) :: Types.LaunchContext.t()
  def launch_context_for(watch_profile_id, launch_reason)
      when is_binary(watch_profile_id) and is_binary(launch_reason) do
    launch_context_for(watch_profile_id, launch_reason, %{})
  end

  @spec launch_context_for(String.t(), String.t(), Types.simulator_settings()) ::
          Types.LaunchContext.t()
  def launch_context_for(watch_profile_id, launch_reason, settings)
      when is_binary(watch_profile_id) and is_binary(launch_reason) and is_map(settings) do
    launch_reason =
      settings
      |> Map.get("launch_reason")
      |> case do
        nil -> parse_launch_reason(launch_reason)
        value -> parse_launch_reason(value)
      end

    profile =
      Map.get(
        WatchModels.profiles_map(),
        watch_profile_id,
        Map.get(WatchModels.profiles_map(), WatchModels.default_id())
      )

    screen = Map.get(profile, "screen") || %{}
    profile_shape = Map.get(profile, "shape")

    display_shape =
      case profile_shape do
        "round" -> "Round"
        _ -> "Rectangular"
      end

    %{
      "launch_reason" => launch_reason,
      "watch_profile_id" => watch_profile_id,
      "watch_model" => Map.get(profile, "name"),
      "shape" => profile_shape,
      "has_microphone" => Map.get(profile, "has_microphone") == true,
      "has_compass" => Map.get(profile, "has_compass") == true,
      "has_speaker" => Map.get(profile, "has_speaker") == true,
      "supports_health" => Map.get(profile, "supports_health") == true,
      "launch_button" => parse_launch_button(Map.get(settings, "launch_button")),
      "quick_launch_action" =>
        parse_quick_launch_action(Map.get(settings, "quick_launch_action")),
      "screen" => %{
        "width" => Map.get(screen, "width") || 144,
        "height" => Map.get(screen, "height") || 168,
        "shape" => display_shape,
        "color_mode" => Map.get(profile, "color_mode") || "Color"
      }
    }
  end

  def launch_context_for(_, _, _), do: launch_context_for(WatchModels.default_id(), "LaunchUser", %{})

  @spec parse_watch_profile_id(Types.wire_input()) :: String.t()
  def parse_watch_profile_id(value) when is_binary(value) do
    normalized = String.downcase(String.trim(value))

    if Map.has_key?(WatchModels.profiles_map(), normalized),
      do: normalized,
      else: WatchModels.default_id()
  end

  def parse_watch_profile_id(_), do: WatchModels.default_id()

  @spec parse_launch_reason(Types.wire_input()) :: String.t()
  def parse_launch_reason(value) when is_binary(value) do
    normalized = String.trim(value)

    if normalized in [
         "LaunchSystem",
         "LaunchUser",
         "LaunchPhone",
         "LaunchWakeup",
         "LaunchWorker",
         "LaunchQuickLaunch",
         "LaunchTimelineAction",
         "LaunchUnknown"
       ] do
      normalized
    else
      "LaunchUser"
    end
  end

  def parse_launch_reason(_), do: "LaunchUser"

  @launch_buttons ~w(Back Up Select Down)

  @quick_launch_actions ~w(
    QuickLaunchNone
    QuickLaunchHold
    QuickLaunchTap
    QuickLaunchCombo
    QuickLaunchUnknown
  )

  @spec parse_launch_button(Types.wire_input()) :: String.t() | nil
  def parse_launch_button(value) when value in [nil, ""], do: nil

  def parse_launch_button(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed in @launch_buttons, do: trimmed, else: nil
  end

  def parse_launch_button(_), do: nil

  @spec parse_quick_launch_action(Types.wire_input()) :: String.t()
  def parse_quick_launch_action(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed in @quick_launch_actions, do: trimmed, else: "QuickLaunchNone"
  end

  def parse_quick_launch_action(_), do: "QuickLaunchNone"

  @spec merge_launch_context_model(Types.app_model(), Types.launch_context()) :: Types.app_model()
  def merge_launch_context_model(model, launch_context)
      when is_map(model) and is_map(launch_context) do
    profile_id = Map.get(launch_context, "watch_profile_id")
    color_mode = launch_context_color_mode(launch_context)
    width = get_in(launch_context, ["screen", "width"])
    height = get_in(launch_context, ["screen", "height"])
    screen_fields = launch_context_screen_fields(launch_context)

    model
    |> Map.put("launch_context", launch_context)
    |> Map.put("watch_profile_id", profile_id)
    |> Map.put("screen_width", width)
    |> Map.put("screen_height", height)
    |> Map.put("supports_color", color_mode == "Color")
    |> patch_runtime_model_screen_fields(screen_fields)
  end

  def merge_launch_context_model(model, _launch_context) when is_map(model), do: model
  def merge_launch_context_model(_model, _launch_context), do: %{}

  @doc false
  @spec launch_context_screen_fields(Types.launch_context()) :: Types.inner_runtime_model()
  def launch_context_screen_fields(launch_context) when is_map(launch_context) do
    width = get_in(launch_context, ["screen", "width"])
    height = get_in(launch_context, ["screen", "height"])

    %{}
    |> maybe_put_screen_field("screenW", width)
    |> maybe_put_screen_field("screenH", height)
    |> Map.put("displayShape", launch_context_display_shape(launch_context))
  end

  def launch_context_screen_fields(_launch_context), do: %{}

  @doc false
  @spec launch_context_display_shape(Types.launch_context()) :: Types.protocol_ctor_value()
  def launch_context_display_shape(launch_context) when is_map(launch_context) do
    case get_in(launch_context, ["screen", "shape"]) do
      %{"ctor" => ctor, "args" => _} = value when is_binary(ctor) ->
        Map.put(value, "args", [])

      %{ctor: ctor, args: _} when is_binary(ctor) ->
        %{"ctor" => ctor, "args" => []}

      "Round" ->
        %{"ctor" => "Round", "args" => []}

      "Rectangular" ->
        %{"ctor" => "Rectangular", "args" => []}

      shape when is_binary(shape) ->
        if String.contains?(String.downcase(shape), "round") do
          %{"ctor" => "Round", "args" => []}
        else
          %{"ctor" => "Rectangular", "args" => []}
        end

      _ ->
        if get_in(launch_context, ["screen", "is_round"]) == true do
          %{"ctor" => "Round", "args" => []}
        else
          %{"ctor" => "Rectangular", "args" => []}
        end
    end
  end

  def launch_context_display_shape(_launch_context),
    do: %{"ctor" => "Rectangular", "args" => []}

  @spec patch_runtime_model_screen_fields(Types.app_model(), Types.inner_runtime_model()) ::
          Types.app_model()
  defp patch_runtime_model_screen_fields(model, screen_fields)
       when is_map(model) and is_map(screen_fields) and map_size(screen_fields) > 0 do
    case Map.get(model, "runtime_model") do
      %{} = runtime_model ->
        fields = screen_fields_for_runtime_model(screen_fields, runtime_model)
        Map.put(model, "runtime_model", Map.merge(runtime_model, fields))

      _ ->
        model
    end
  end

  defp screen_fields_for_runtime_model(screen_fields, runtime_model) when is_map(runtime_model) do
    Enum.reduce(["screenW", "screenH", "displayShape"], screen_fields, fn key, fields ->
      if Map.has_key?(runtime_model, key) or Map.has_key?(runtime_model, String.to_atom(key)) do
        fields
      else
        Map.delete(fields, key)
      end
    end)
  end

  defp maybe_put_screen_field(map, _key, value) when not is_integer(value) or value <= 0, do: map
  defp maybe_put_screen_field(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_runtime_value(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put_runtime_value(map, key, value), do: Map.put(map, key, value)

  @spec launch_context_color_mode(Types.LaunchContext.wire_map()) :: String.t()
  def launch_context_color_mode(launch_context) when is_map(launch_context) do
    cond do
      get_in(launch_context, ["screen", "color_mode"]) in ["Color", "BlackWhite"] ->
        get_in(launch_context, ["screen", "color_mode"])

      get_in(launch_context, ["screen", "colorMode"]) in ["Color", "BlackWhite"] ->
        get_in(launch_context, ["screen", "colorMode"])

      get_in(launch_context, ["screen", "is_color"]) == true ->
        "Color"

      get_in(launch_context, ["screen", "is_color"]) == false ->
        "BlackWhite"

      true ->
        "Color"
    end
  end

  defp merge_launch_context_view_tree(view_tree, launch_context)
       when is_map(view_tree) and is_map(launch_context) do
    width = get_in(launch_context, ["screen", "width"]) || 144
    height = get_in(launch_context, ["screen", "height"]) || 168
    box = %{"x" => 0, "y" => 0, "w" => width, "h" => height}

    if map_size(view_tree) == 0 do
      %{"type" => "root", "children" => [], "box" => box}
    else
      Map.put(view_tree, "box", box)
    end
  end

  defp merge_launch_context_view_tree(view_tree, _launch_context) when is_map(view_tree),
    do: view_tree

  defp merge_launch_context_view_tree(_view_tree, _launch_context),
    do: %{"type" => "root", "children" => []}

  @spec watch_profile_list_items() :: [Types.watch_profile_list_item()]
  def watch_profile_list_items do
    profiles = WatchModels.profiles_map()

    WatchModels.ordered_ids()
    |> Enum.map(fn id ->
      profile = Map.get(profiles, id, %{})

      profile
      |> Map.put("id", id)
      |> Map.put("label", watch_profile_label(profile))
    end)
  end

  @spec watch_profile_label(Types.watch_profile()) :: String.t()
  defp watch_profile_label(profile) when is_map(profile) do
    name = Map.get(profile, "name") || "Watch"
    screen = Map.get(profile, "screen") || %{}
    width = Map.get(screen, "width") || 0
    height = Map.get(screen, "height") || 0

    color =
      case Map.get(profile, "color_mode") do
        "Color" -> "color"
        "BlackWhite" -> "mono"
        _ -> "mono"
      end

    "#{name} (#{width}x#{height}, #{color})"
  end
end
