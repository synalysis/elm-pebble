defmodule Ide.Debugger.RuntimeSurfaces do
  @moduledoc false

  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.WatchModels

  @spec default_watch(map() | nil) :: Surface.surface_map()
  def default_watch(launch_context \\ nil)

  def default_watch(nil) do
    default_watch(launch_context_for(WatchModels.default_id(), "LaunchUser"))
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

  @spec protocol_model(String.t()) :: map()
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
      model = if is_map(model), do: model, else: %{}
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
  def apply_launch_context(state, launch_reason) when is_map(state) and is_binary(launch_reason) do
    watch_profile_id = parse_watch_profile_id(Map.get(state, :watch_profile_id))
    launch_reason = parse_launch_reason(launch_reason)
    launch_context = launch_context_for(watch_profile_id, launch_reason)

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
      "supports_health" => Map.get(profile, "supports_health") == true,
      "screen" => %{
        "width" => Map.get(screen, "width") || 144,
        "height" => Map.get(screen, "height") || 168,
        "shape" => display_shape,
        "color_mode" => Map.get(profile, "color_mode") || "Color"
      }
    }
  end

  def launch_context_for(_, _), do: launch_context_for(WatchModels.default_id(), "LaunchUser")

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
         "LaunchUnknown"
       ] do
      normalized
    else
      "LaunchUser"
    end
  end

  def parse_launch_reason(_), do: "LaunchUser"

  @spec merge_launch_context_model(map(), map()) :: map()
  def merge_launch_context_model(model, launch_context)
      when is_map(model) and is_map(launch_context) do
    profile_id = Map.get(launch_context, "watch_profile_id")
    color_mode = launch_context_color_mode(launch_context)
    width = get_in(launch_context, ["screen", "width"])
    height = get_in(launch_context, ["screen", "height"])

    model
    |> Map.put("launch_context", launch_context)
    |> Map.put("watch_profile_id", profile_id)
    |> Map.put("screen_width", width)
    |> Map.put("screen_height", height)
    |> Map.put("supports_color", color_mode == "Color")
  end

  def merge_launch_context_model(model, _launch_context) when is_map(model), do: model
  def merge_launch_context_model(_model, _launch_context), do: %{}

  defp maybe_put_runtime_value(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put_runtime_value(map, key, value), do: Map.put(map, key, value)

  @spec launch_context_color_mode(map()) :: String.t()
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

  defp watch_profile_label(_), do: "Watch"
end
