defmodule Elmx.Runtime.Pebble do
  @moduledoc """
  Pebble platform lowering and runtime stubs for generated Elixir code.
  """

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.Generator
  alias Elmx.Runtime.Pebble.SpecialValues
  alias Elmx.Runtime.Values
  alias Elmx.Types

  @spec rewrite_qualified_call(String.t(), [term()]) :: Types.rewrite_result()
  def rewrite_qualified_call(target, args), do: SpecialValues.rewrite(target, args)

  @spec special_call?(String.t()) :: boolean()
  def special_call?(target) when is_binary(target) do
    String.starts_with?(target, "Pebble.") or String.starts_with?(target, "Platform.") or
      String.starts_with?(target, "Companion.") or
      String.starts_with?(target, "Elm.Kernel.PebbleWatch.") or
      String.starts_with?(target, "Elm.Kernel.PebblePhone.")
  end

  @spec special_call_code(String.t()) :: {:ok, String.t()} | :error
  def special_call_code(_target), do: :error

  @spec runtime_call(String.t(), iodata()) :: String.t()
  def runtime_call(function, arg_code) do
    "Elmx.Runtime.Pebble.runtime_dispatch(#{inspect(function)}, [#{IO.iodata_to_binary(arg_code)}])"
  end

  @spec runtime_dispatch(String.t(), list()) :: Types.wire_cmd() | term()
  def runtime_dispatch(function, args) when is_binary(function) and is_list(args) do
    if String.starts_with?(function, "elmc_") do
      case Generator.apply(function, args) do
        {:ok, value} -> value
        :error -> raise ArgumentError, "unsupported elmc runtime call #{function}"
      end
    else
      dispatch_elmx(function, args)
    end
  end

  defp dispatch_elmx(function, args) do
    case function do
      "elmx_cmd_batch" -> Values.cmd_batch(args)
      "elmx_http_get" -> Elmx.Runtime.Http.get(args)
      "elmx_http_post" -> Elmx.Runtime.Http.post(args)
      "elmx_http_request" -> Elmx.Runtime.Http.request(args)
      "elmx_http_expect_string" -> Elmx.Runtime.Http.expect_string(args)
      "elmx_http_expect_json" -> Elmx.Runtime.Http.expect_json(args)
      "elmx_http_header" -> Elmx.Runtime.Http.header(args)
      "elmx_http_string_body" -> Elmx.Runtime.Http.string_body(args)
      "elmx_http_json_body" -> Elmx.Runtime.Http.json_body(args)
      "elmx_http_empty_body" -> Elmx.Runtime.Http.empty_body(args)
      "elmx_ui_window_stack" -> apply_ui(:window_stack, args)
      "elmx_ui_window" -> apply_ui(:window, args)
      "elmx_ui_canvas_layer" -> apply_ui(:canvas_layer, args)
      "elmx_ui_group" -> apply_ui(:group, args)
      "elmx_ui_context" -> apply_ui(:context, args)
      "elmx_ui_draw_bitmap_in_rect" -> apply_ui(:draw_bitmap_in_rect, args)
      "elmx_ui_clear" -> apply_ui(:clear, args)
      "elmx_ui_fill_rect" -> apply_ui(:fill_rect, args)
      "elmx_ui_text" -> apply_ui(:text, args)
      "elmx_ui_text_int" -> apply_ui(:text_int, args)
      "elmx_ui_text_label" -> apply_ui(:text_label, args)
      "elmx_ui_rect" -> apply_ui(:rect, args)
      "elmx_ui_line" -> apply_ui_line(args)
      "elmx_ui_circle" -> apply_ui(:circle, args)
      "elmx_ui_fill_circle" -> apply_ui(:fill_circle, args)
      "elmx_ui_fill_radial" -> apply_ui(:fill_radial, args)
      "elmx_list_repeat" -> list_repeat(args)
      "elmx_core_list_repeat" -> list_repeat(args)
      "elmx_basics_to_float" -> basics_to_float(args)
      "elmx_basics_floor" -> basics_floor(args)
      "elmx_basics_ceiling" -> basics_ceiling(args)
      "elmx_basics_round" -> basics_round(args)
      "elmx_basics_truncate" -> basics_truncate(args)
      "elmx_ui_pixel" -> apply_ui(:pixel, args)
      "elmx_ui_stroke_width" -> ui_context_setting("stroke_width", args)
      "elmx_ui_antialiased" -> ui_context_setting("antialiased", args)
      "elmx_ui_stroke_color" -> ui_context_setting("stroke_color", args)
      "elmx_ui_fill_color" -> ui_context_setting("fill_color", args)
      "elmx_ui_text_color" -> ui_context_setting("text_color", args)
      "elmx_ui_align_left" -> ui_context_setting("align_left", args)
      "elmx_ui_align_center" -> ui_context_setting("align_center", args)
      "elmx_ui_align_right" -> ui_context_setting("align_right", args)
      "elmx_ui_word_wrap" -> ui_context_setting("word_wrap", args)
      "elmx_ui_trailing_ellipsis" -> ui_context_setting("trailing_ellipsis", args)
      "elmx_ui_fill_overflow" -> ui_context_setting("fill_overflow", args)
      "elmx_core_maybe_with_default" -> apply_core(:maybe_with_default, args)
      "elmx_core_maybe_map" -> apply_core(:maybe_map, args)
      "elmx_core_maybe_and_then" -> apply_core(:maybe_and_then, args)
      "elmx_core_maybe_map2" -> apply_core(:maybe_map2, args)
      "elmx_core_result_map" -> apply_core(:result_map, args)
      "elmx_core_result_map_error" -> apply_core(:result_map_error, args)
      "elmx_core_result_with_default" -> apply_core(:result_with_default, args)
      "elmx_core_result_and_then" -> apply_core(:result_and_then, args)
      "elmx_core_random_generator" -> apply_core(:random_generator, args)
      "elmx_cmd_random_generate" -> random_generate_cmd(args)
      "elmx_light_enable" -> Cmd.effect("light", variant: "enable")
      "elmx_light_disable" -> Cmd.effect("light", variant: "disable")
      "elmx_light_interaction" -> Cmd.effect("light", variant: "interaction")
      "elmx_platform_launch_reason_to_int" -> platform_launch_reason(args)
      "elmx_platform_display_shape_is_round" -> platform_display_shape_is_round(args)
      "elmx_platform_color_capability_is_color" -> platform_color_capability_is_color(args)
      "elmx_platform_application" -> Cmd.effect("platform", variant: "application")
      "elmx_platform_watchface" -> Cmd.effect("platform", variant: "watchface")
      "elmx_time_now" -> Elmx.Runtime.Core.Time.now()
      "elmx_time_get_zone_name" -> Elmx.Runtime.Core.Time.get_zone_name()
      "elmx_kernel_time_now_millis" -> :os.system_time(:millisecond)
      "elmx_kernel_time_zone_offset_minutes" -> Elmx.Runtime.Core.Time.zone_offset_minutes()
      "elmx_time_current_date_time" -> device_stub("current_date_time", args)
      "elmx_time_current_time_string" -> device_stub("current_time_string", args)
      "elmx_time_clock_style_24h" -> device_stub("clock_style_24h", args)
      "elmx_time_timezone_is_set" -> device_stub("timezone_is_set", args)
      "elmx_time_timezone" -> device_stub("timezone", args)
      "elmx_watch_info_get_model" -> device_stub("watch_model", args)
      "elmx_watch_info_get_color" -> device_stub("watch_color", args)
      "elmx_watch_info_get_firmware_version" -> device_stub("firmware_version", args)
      "elmx_system_battery_level" -> device_stub("battery_level", args)
      "elmx_system_connection_status" -> device_stub("connection_status", args)
      "elmx_events_batch" -> Cmd.none()
      "elmx_events_on_minute_change" -> subscription_cmd("Pebble.Events.onMinuteChange", args)
      "elmx_button_on" -> subscription_cmd("Pebble.Button.on", args)
      "elmx_accel_on_tap" -> subscription_cmd("Pebble.Accel.onTap", args)
      "elmx_events_on_second_change" -> subscription_cmd("Pebble.Events.onSecondChange", args)
      "elmx_button_on_press" -> subscription_cmd("Pebble.Button.onPress", args)
      "elmx_cmd_timer_after" -> timer_after_cmd(args)
      "elmx_storage_read_int" -> storage_read_int_cmd(args)
      "elmx_storage_read_string" -> storage_read_string_cmd(args)
      "elmx_cmd_backlight" -> backlight_cmd(args)
      "elmx_storage_write_int" -> storage_write_int_cmd(args)
      "elmx_storage_write_string" -> storage_write_string_cmd(args)
      "elmx_storage_delete" -> storage_delete_cmd(args)
      "elmx_frame_every" -> frame_every_cmd(args)
      "elmx_vibes_short_pulse" -> Cmd.effect("vibes", variant: "short_pulse")
      "elmx_vibes_long_pulse" -> Cmd.effect("vibes", variant: "long_pulse")
      "elmx_vibes_double_pulse" -> Cmd.effect("vibes", variant: "double_pulse")
      "elmx_vibes_pattern" -> Cmd.effect("vibes", variant: "pattern", pattern: List.first(args))
      "elmx_vibes_cancel" -> Cmd.effect("vibes", variant: "cancel")
      "elmx_button_on_release" -> subscription_cmd("Pebble.Button.onRelease", args)
      "elmx_collision_rect_rect" -> collision_rect_rect(args)
      "elmx_datalog_tag" -> datalog_tag_value(args)
      "elmx_datalog_log_int32" -> datalog_log_int32_cmd(args)
      "elmx_datalog_log_bytes" -> datalog_log_bytes_cmd(args)
      "elmx_dictation_start" -> Cmd.dictation_start()
      "elmx_dictation_stop" -> Cmd.dictation_stop()
      "elmx_companion_send" -> companion_send_cmd(args)
      "elmx_companion_send_phone" -> companion_send_phone_cmd(args)
      "elmx_companion_storage_get" -> companion_storage_get_cmd(args)
      "elmx_companion_storage_set" -> companion_storage_set_cmd(args)
      "elmx_companion_storage_remove" -> companion_storage_remove_cmd(args)
      "elmx_companion_preferences_get" -> companion_preferences_get_cmd(args)
      "elmx_companion_preferences_set" -> companion_preferences_set_cmd(args)
      "elmx_companion_bridge_cmd" -> companion_bridge_cmd(args)
      "elmx_companion_phone_send" -> companion_phone_send_cmd(args)
      "elmx_companion_send_bridge_command" -> companion_send_bridge_command_cmd(args)
      "elmx_companion_websocket_connect" -> companion_websocket_connect_cmd(args)
      "elmx_companion_websocket_disconnect" -> companion_websocket_disconnect_cmd(args)
      "elmx_companion_websocket_send" -> companion_websocket_send_cmd(args)
      "elmx_json_encode_object" -> Elmx.Runtime.Json.Encode.object(List.first(args) || [])
      "elmx_json_encode_string" -> Elmx.Runtime.Json.Encode.string(List.first(args))
      "elmx_json_encode_int" -> Elmx.Runtime.Json.Encode.int(List.first(args))
      "elmx_json_encode_bool" -> Elmx.Runtime.Json.Encode.bool(List.first(args))
      "elmx_json_encode_list" -> json_encode_list(args)
      "elmx_json_encode_array" -> json_encode_list(args)
      "elmx_json_encode_set" -> json_encode_list(args)
      "elmx_json_encode_dict" -> json_encode_dict(args)
      "elmx_json_encode_null" -> Elmx.Runtime.Json.Encode.null()
      "elmx_json_encode_float" -> json_encode_float(args)
      "elmx_json_encode_encode" -> json_encode_encode(args)
      "elmx_unobstructed_current_bounds" -> unobstructed_current_bounds_cmd(args)
      "elmx_compass_peek" -> compass_peek_cmd(args)
      "elmx_ui_round_rect" -> apply_ui(:round_rect, args)
      "elmx_ui_arc" -> apply_ui(:arc, args)
      "elmx_ui_path" -> apply_ui(:path, args)
      "elmx_ui_path_outline" -> apply_ui(:path_outline, args)
      "elmx_ui_path_filled" -> apply_ui(:path_filled, args)
      "elmx_ui_path_outline_open" -> apply_ui(:path_outline_open, args)
      "elmx_ui_rotation_from_pebble_angle" -> List.first(args) || 0
      "elmx_ui_rotation_from_degrees" -> apply_ui(:rotation_from_degrees, args)
      "elmx_ui_draw_vector_at" -> apply_ui(:draw_vector_at, args)
      "elmx_ui_draw_vector_sequence_at" -> apply_ui(:draw_vector_sequence_at, args)
      "elmx_ui_draw_bitmap_sequence_at" -> apply_ui(:draw_bitmap_sequence_at, args)
      "elmx_ui_draw_rotated_bitmap" -> apply_ui(:draw_rotated_bitmap, args)
      "elmx_ui_compositing_mode" -> apply_ui(:compositing_mode, args)
      "elmx_list_cons" -> list_cons(args)
      "elmx_math_clamp" -> math_clamp(args)
      "elmx_basics_compare" -> apply_core(:basics_compare, args)
      "elmx_ui_named_color" -> apply_ui(:named_color, args)
      other when is_binary(other) ->
        if kernel_runtime_function?(other) do
          kernel_runtime_stub(other, args)
        else
          raise ArgumentError, "unsupported elmx runtime call #{other}"
        end
    end
  end

  defp apply_ui(fun, args) do
    apply(Elmx.Runtime.Pebble.Ui, fun, args)
  end

  defp apply_ui_line([x1, y1, x2, y2, color]) when is_integer(x1),
    do: apply_ui(:line, [%{x: x1, y: y1}, %{x: x2, y: y2}, color])

  defp apply_ui_line(args), do: apply_ui(:line, args)

  defp apply_core(fun, args), do: apply(Elmx.Runtime.Core, fun, args)

  defp list_repeat([n, value]), do: Elmx.Runtime.Core.list_repeat(n, value)
  defp list_repeat(_), do: []

  defp basics_to_float([value]) when is_float(value), do: value
  defp basics_to_float([value]) when is_integer(value), do: value * 1.0
  defp basics_to_float([value]) when is_number(value), do: value * 1.0
  defp basics_to_float(_), do: 0.0

  defp basics_floor([value]) when is_number(value), do: floor(value)
  defp basics_floor(_), do: 0

  defp basics_ceiling([value]) when is_number(value), do: ceil(value)
  defp basics_ceiling(_), do: 0

  defp basics_round([value]) when is_number(value), do: round(value)
  defp basics_round(_), do: 0

  defp basics_truncate([value]) when is_number(value), do: trunc(value)
  defp basics_truncate(_), do: 0

  defp list_cons([head, tail]) when is_list(tail), do: [head | tail]
  defp list_cons([head | rest]), do: [head | List.first(rest) || []]
  defp list_cons(_), do: []

  defp math_clamp([lo, hi, value]) when is_number(lo) and is_number(hi) and is_number(value),
    do: max(lo, min(hi, value))

  defp math_clamp([lo, hi, value]), do: max(lo, min(hi, value))
  defp math_clamp(_), do: 0

  defp random_generate_cmd([to_msg, generator]) do
    value = Elmx.Runtime.Core.random_int(generator)
    Cmd.device("random", to_msg, value)
  end

  defp random_generate_cmd(_), do: Cmd.none()

  defp platform_launch_reason([reason]), do: Elmx.Runtime.LaunchContext.launch_reason_to_int(reason)
  defp platform_launch_reason(_), do: Elmx.Runtime.LaunchContext.launch_reason_to_int(nil)

  defp platform_display_shape_is_round([shape]), do: platform_display_shape_is_round_value(shape)
  defp platform_display_shape_is_round(_), do: false

  defp platform_display_shape_is_round_value(%{"ctor" => ctor}) when is_binary(ctor),
    do: String.contains?(ctor, "Round") or String.contains?(ctor, "round")

  defp platform_display_shape_is_round_value({ctor, _}) when is_atom(ctor),
    do: ctor in [:Round, :ChinookRound, :EmeryRound]

  defp platform_display_shape_is_round_value(_), do: false

  defp platform_color_capability_is_color([mode]), do: platform_color_capability_is_color_value(mode)
  defp platform_color_capability_is_color(_), do: false

  defp platform_color_capability_is_color_value(:Color), do: true
  defp platform_color_capability_is_color_value("Color"), do: true
  defp platform_color_capability_is_color_value(%{"ctor" => "Color"}), do: true
  defp platform_color_capability_is_color_value({:Color}), do: true
  defp platform_color_capability_is_color_value(_), do: false

  defp ui_context_setting(key, [value]), do: Elmx.Runtime.Pebble.Ui.context_setting(key, value)
  defp ui_context_setting(key, []), do: Elmx.Runtime.Pebble.Ui.context_setting(key, 0)
  defp ui_context_setting(key, args), do: Elmx.Runtime.Pebble.Ui.context_setting(key, List.first(args))

  defp timer_after_cmd([ms, message]) when is_integer(ms), do: Cmd.timer_after(ms, message)
  defp timer_after_cmd([ms | rest]) when is_integer(ms), do: Cmd.timer_after(ms, List.first(rest))
  defp timer_after_cmd(_), do: Cmd.none()

  defp companion_send_cmd([message]), do: Cmd.protocol_watch_to_phone(message)
  defp companion_send_cmd(_), do: Cmd.none()

  defp companion_send_phone_cmd([message]), do: Cmd.protocol_phone_to_watch(message)
  defp companion_send_phone_cmd(_), do: Cmd.none()

  defp companion_storage_get_cmd([key, callback]) when is_binary(key),
    do: Cmd.companion_bridge("storage", "get", key: key, callback: callback)

  defp companion_storage_get_cmd(_), do: Cmd.none()

  defp companion_storage_set_cmd([key, value]) when is_binary(key),
    do: Cmd.companion_bridge("storage", "set", key: key, value: companion_storage_value_wire(value))

  defp companion_storage_set_cmd(_), do: Cmd.none()

  defp companion_storage_remove_cmd([key]) when is_binary(key),
    do: Cmd.companion_bridge("storage", "remove", key: key, callback: "Ok")

  defp companion_storage_remove_cmd(_), do: Cmd.none()

  defp companion_preferences_get_cmd([key, callback]) when is_binary(key),
    do: Cmd.companion_bridge("preferences", "get", key: key, callback: callback)

  defp companion_preferences_get_cmd(_), do: Cmd.none()

  defp companion_preferences_set_cmd([key, value]) when is_binary(key),
    do: Cmd.companion_bridge("preferences", "set", key: key, value: value)

  defp companion_preferences_set_cmd(_), do: Cmd.none()

  defp companion_bridge_cmd([api, op, callback]) when is_binary(api) and is_binary(op),
    do: Cmd.companion_bridge(api, op, callback: callback)

  defp companion_bridge_cmd(_), do: Cmd.none()

  defp companion_phone_send_cmd([callback, request]),
    do: companion_bridge_from_envelope(callback, request)

  defp companion_phone_send_cmd(_), do: Cmd.none()

  defp companion_send_bridge_command_cmd([envelope]),
    do: companion_bridge_from_envelope("Unknown", envelope)

  defp companion_send_bridge_command_cmd(_), do: Cmd.none()

  defp companion_bridge_from_envelope(callback, request) do
    case companion_command_envelope(request) do
      %{"api" => api, "op" => op} = envelope when is_binary(api) and is_binary(op) ->
        Cmd.companion_bridge(api, op,
          callback: callback,
          bridge_id: Map.get(envelope, "id"),
          payload: Map.get(envelope, "payload", %{})
        )

      _ ->
        Cmd.none()
    end
  end

  defp companion_command_envelope({:Request, envelope, _}), do: normalize_command_envelope(envelope)

  defp companion_command_envelope(%{"ctor" => "Request", "args" => [envelope | _]}),
    do: normalize_command_envelope(envelope)

  defp companion_command_envelope(envelope), do: normalize_command_envelope(envelope)

  defp normalize_command_envelope(envelope) when is_map(envelope) do
    %{
      "id" => envelope_field(envelope, "id"),
      "api" => envelope_field(envelope, "api"),
      "op" => envelope_field(envelope, "op"),
      "payload" => envelope_field(envelope, "payload") || %{}
    }
  end

  defp normalize_command_envelope(_), do: %{}

  defp envelope_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp companion_websocket_connect_cmd([url, callback]) when is_binary(url) do
    Cmd.companion_bridge("webSocket", "connect",
      callback: callback,
      bridge_id: "webSocket-connect",
      payload: %{"url" => url}
    )
  end

  defp companion_websocket_connect_cmd(_), do: Cmd.none()

  defp companion_websocket_disconnect_cmd([callback]) do
    Cmd.companion_bridge("webSocket", "disconnect",
      callback: callback,
      bridge_id: "webSocket-disconnect"
    )
  end

  defp companion_websocket_disconnect_cmd(_), do: Cmd.none()

  defp companion_websocket_send_cmd([message, callback]) when is_binary(message) do
    Cmd.companion_bridge("webSocket", "send",
      callback: callback,
      bridge_id: "webSocket-send",
      payload: %{"message" => message}
    )
  end

  defp companion_websocket_send_cmd(_), do: Cmd.none()

  defp companion_storage_value_wire(%{"ctor" => "StringValue", "args" => [text]}), do: %{"ctor" => "StringValue", "args" => [text]}
  defp companion_storage_value_wire(%{ctor: "StringValue", args: [text]}), do: %{"ctor" => "StringValue", "args" => [text]}
  defp companion_storage_value_wire({:StringValue, text}), do: %{"ctor" => "StringValue", "args" => [text]}
  defp companion_storage_value_wire(other), do: Values.wire_value(other)

  defp json_encode_list([encoder, items]) when is_function(encoder, 1),
    do: Elmx.Runtime.Json.Encode.list(encoder, items)

  defp json_encode_list([_encoder, items]) when is_list(items), do: items
  defp json_encode_list([items]) when is_list(items), do: items
  defp json_encode_list(_), do: []

  defp json_encode_float([value]), do: Elmx.Runtime.Json.Encode.float(value)
  defp json_encode_float(_), do: 0.0

  defp json_encode_encode([indent, value]) when is_integer(indent),
    do: Elmx.Runtime.Json.Encode.encode(indent, value)

  defp json_encode_encode(_), do: "null"

  defp json_encode_dict([key_fn, val_fn, dict]) when is_function(key_fn, 1) and is_function(val_fn, 1) do
    dict
    |> Map.new(fn {k, v} -> {key_fn.(k), val_fn.(v)} end)
  end

  defp json_encode_dict([_key_fn, _val_fn, dict]) when is_map(dict), do: dict
  defp json_encode_dict(_), do: %{}

  defp unobstructed_current_bounds_cmd(args) when is_list(args) do
    callback = List.last(args)
    Cmd.unobstructed_bounds_peek(callback)
  end

  defp unobstructed_current_bounds_cmd(_), do: Cmd.none()

  defp datalog_tag_value([tag]) when is_integer(tag), do: Values.ctor("Tag", [tag])
  defp datalog_tag_value(_), do: Values.ctor("Tag", [0])

  defp datalog_log_int32_cmd([tag, value]) when is_integer(value), do: Cmd.data_log_int32(tag, value)
  defp datalog_log_int32_cmd(_), do: Cmd.none()

  defp datalog_log_bytes_cmd([tag, bytes]) when is_list(bytes), do: Cmd.data_log_bytes(tag, bytes)
  defp datalog_log_bytes_cmd(_), do: Cmd.none()

  defp storage_read_int_cmd([key, callback, default]) when is_integer(key),
    do: Cmd.storage_read_int(key, callback, default)

  defp storage_read_int_cmd([key, callback]), do: Cmd.storage_read_int(key, callback, 0)
  defp storage_read_int_cmd(_), do: Cmd.none()

  defp storage_read_string_cmd([key, callback, default]) when is_integer(key),
    do: Cmd.storage_read_string(key, callback, default)

  defp storage_read_string_cmd([key, callback]), do: Cmd.storage_read_string(key, callback, "")
  defp storage_read_string_cmd(_), do: Cmd.none()

  defp storage_write_int_cmd([key, value]) when is_integer(key), do: Cmd.storage_write_int(key, value)
  defp storage_write_int_cmd(_), do: Cmd.none()

  defp storage_write_string_cmd([key, value]) when is_integer(key),
    do: Cmd.storage_write_string(key, value)

  defp storage_write_string_cmd(_), do: Cmd.none()

  defp storage_delete_cmd([key]) when is_integer(key), do: Cmd.storage_delete(key)
  defp storage_delete_cmd(_), do: Cmd.none()

  defp collision_rect_rect([a, b]) when is_map(a) and is_map(b) do
    ax = int_field(a, "x")
    ay = int_field(a, "y")
    aw = int_field(a, "w")
    ah = int_field(a, "h")
    bx = int_field(b, "x")
    by = int_field(b, "y")
    bw = int_field(b, "w")
    bh = int_field(b, "h")

    ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
  end

  defp collision_rect_rect(_), do: false

  defp int_field(map, key) do
    Map.get(map, key) || Map.get(map, String.to_atom(key)) || 0
  end

  defp subscription_cmd(target, args) when is_binary(target) do
    callback = subscription_callback(args)
    Cmd.subscription_register(target, callback: callback)
  end

  defp subscription_callback([callback | _]), do: callback
  defp subscription_callback(_), do: "Tick"

  defp frame_every_cmd([ms, callback]) when is_integer(ms) do
    Cmd.subscription_register("Pebble.Frame.every",
      interval_ms: ms,
      callback: callback
    )
  end

  defp frame_every_cmd([ms | rest]) when is_integer(ms) do
    frame_every_cmd([ms, List.first(rest)])
  end

  defp frame_every_cmd(_), do: Cmd.subscription_register("Pebble.Frame.every", interval_ms: 33)

  defp backlight_cmd([maybe]) do
    Cmd.backlight_from_maybe(maybe)
  end

  defp backlight_cmd(_), do: Cmd.backlight_from_maybe(:Nothing)

  defp device_stub(kind, [callback]) do
    Cmd.device(kind, callback, device_stub_value(kind))
  end

  defp device_stub(kind, args) do
    callback = List.first(args)
    Cmd.device(kind, callback, device_stub_value(kind))
  end

  defp device_stub_value("current_date_time") do
    %{
      "year" => 2026,
      "month" => 1,
      "day" => 1,
      "dayOfWeek" => %{"ctor" => "Thursday", "args" => []},
      "hour" => 12,
      "minute" => 0,
      "second" => 0,
      "utcOffsetMinutes" => 0
    }
  end

  defp device_stub_value("current_time_string"), do: "12:00"
  defp device_stub_value("clock_style_24h"), do: true
  defp device_stub_value("timezone_is_set"), do: true
  defp device_stub_value("timezone"), do: "UTC"
  defp device_stub_value("watch_model"), do: %{"ctor" => "PebbleTime", "args" => []}
  defp device_stub_value("firmware_version"), do: %{"major" => 4, "minor" => 4, "patch" => 0}
  defp device_stub_value("watch_color"), do: %{"ctor" => "Black", "args" => []}
  defp device_stub_value("battery_level"), do: 88
  defp device_stub_value("health_supported"), do: false
  defp device_stub_value("health_value"), do: %{"value" => 0}
  defp device_stub_value("health_sum_today"), do: %{"value" => 0}
  defp device_stub_value("health_sum"), do: %{"value" => 0}
  defp device_stub_value("health_accessible"), do: true
  defp device_stub_value("connection_status"), do: true

  defp device_stub_value("unobstructed_bounds"),
    do: %{"x" => 0, "y" => 0, "w" => 144, "h" => 168}

  defp device_stub_value(_), do: nil

  defp kernel_runtime_function?(name) when is_binary(name) do
    String.starts_with?(name, "elmx_kernel_pebble_watch_") or
      String.starts_with?(name, "elmx_kernel_pebble_phone_")
  end

  defp kernel_runtime_stub(function, args) do
    case function do
      "elmx_kernel_pebble_watch_get_current_time_string" ->
        device_stub("current_time_string", args)

      "elmx_kernel_pebble_watch_get_current_date_time" ->
        device_stub("current_date_time", args)

      "elmx_kernel_pebble_watch_get_battery_level" ->
        device_stub("battery_level", args)

      "elmx_kernel_pebble_watch_get_connection_status" ->
        device_stub("connection_status", args)

      "elmx_kernel_pebble_watch_get_clock_style_24h" ->
        device_stub("clock_style_24h", args)

      "elmx_kernel_pebble_watch_get_timezone_is_set" ->
        device_stub("timezone_is_set", args)

      "elmx_kernel_pebble_watch_get_timezone" ->
        device_stub("timezone", args)

      "elmx_kernel_pebble_watch_get_watch_model" ->
        device_stub("watch_model", args)

      "elmx_kernel_pebble_watch_get_color" ->
        device_stub("watch_color", args)

      "elmx_kernel_pebble_watch_get_firmware_version" ->
        device_stub("firmware_version", args)

      "elmx_kernel_pebble_watch_storage_read_string" ->
        storage_read_string_cmd(args)

      "elmx_kernel_pebble_watch_storage_read_int" ->
        storage_read_int_cmd(args)

      "elmx_kernel_pebble_watch_storage_write_int" ->
        storage_write_int_cmd(args)

      "elmx_kernel_pebble_watch_storage_write_string" ->
        storage_write_string_cmd(args)

      "elmx_kernel_pebble_watch_storage_delete" ->
        storage_delete_cmd(args)

      "elmx_kernel_pebble_watch_health_supported" ->
        health_device_cmd("health_supported", args)

      "elmx_kernel_pebble_watch_health_value" ->
        health_device_cmd("health_value", args)

      "elmx_kernel_pebble_watch_health_sum_today" ->
        health_device_cmd("health_sum_today", args)

      "elmx_kernel_pebble_watch_health_sum" ->
        health_device_cmd("health_sum", args)

      "elmx_kernel_pebble_watch_health_accessible" ->
        health_device_cmd("health_accessible", args)

      "elmx_kernel_pebble_watch_compass_current" ->
        compass_peek_cmd(args)

      "elmx_kernel_pebble_phone_http_get" ->
        Elmx.Runtime.Http.get(args)

      "elmx_kernel_pebble_phone_http_post" ->
        Elmx.Runtime.Http.post(args)

      "elmx_kernel_pebble_phone_http_request" ->
        Elmx.Runtime.Http.request(args)

      "elmx_kernel_pebble_phone_http_expect_string" ->
        Elmx.Runtime.Http.expect_string(args)

      "elmx_kernel_pebble_phone_http_expect_json" ->
        Elmx.Runtime.Http.expect_json(args)

      _ ->
        Cmd.none()
    end
  end

  defp compass_peek_cmd(args) when is_list(args) do
    callback = List.last(args)
    Cmd.compass_peek(callback)
  end

  defp health_device_cmd(kind, args) when is_binary(kind) and is_list(args) do
    callback = List.last(args)
    device_stub(kind, [callback])
  end
end
