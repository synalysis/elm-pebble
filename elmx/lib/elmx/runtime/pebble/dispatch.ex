defmodule Elmx.Runtime.Pebble.Dispatch do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Pebble.DeviceStubs
  alias Elmx.Runtime.Pebble.Dispatch.Basics
  alias Elmx.Runtime.Pebble.Dispatch.Companion
  alias Elmx.Runtime.Pebble.Dispatch.Effects
  alias Elmx.Runtime.Pebble.Dispatch.Json, as: DispatchJson
  alias Elmx.Runtime.Pebble.Dispatch.Kernel
  alias Elmx.Runtime.Pebble.Dispatch.Platform
  alias Elmx.Runtime.Pebble.Dispatch.Storage
  alias Elmx.Types

  # Companion
  defdelegate companion_send_cmd(args), to: Companion, as: :send_cmd
  defdelegate companion_send_phone_cmd(args), to: Companion, as: :send_phone_cmd
  defdelegate companion_storage_get_cmd(args), to: Companion, as: :storage_get_cmd
  defdelegate companion_storage_set_cmd(args), to: Companion, as: :storage_set_cmd
  defdelegate companion_storage_remove_cmd(args), to: Companion, as: :storage_remove_cmd
  defdelegate companion_preferences_get_cmd(args), to: Companion, as: :preferences_get_cmd
  defdelegate companion_preferences_set_cmd(args), to: Companion, as: :preferences_set_cmd
  defdelegate companion_preferences_decode_response(args), to: Companion, as: :preferences_decode_response
  defdelegate companion_configuration_on_closed(args), to: Companion, as: :configuration_on_closed
  defdelegate companion_bridge_cmd(args), to: Companion, as: :bridge_cmd
  defdelegate companion_phone_send_cmd(args), to: Companion, as: :phone_send_cmd
  defdelegate companion_send_bridge_command_cmd(args), to: Companion, as: :send_bridge_command_cmd
  defdelegate companion_websocket_connect_cmd(args), to: Companion, as: :websocket_connect_cmd
  defdelegate companion_websocket_disconnect_cmd(args), to: Companion, as: :websocket_disconnect_cmd
  defdelegate companion_websocket_send_cmd(args), to: Companion, as: :websocket_send_cmd

  # JSON encode
  defdelegate json_encode_object(args), to: DispatchJson, as: :encode_object
  defdelegate json_encode_string(args), to: DispatchJson, as: :encode_string
  defdelegate json_encode_int(args), to: DispatchJson, as: :encode_int
  defdelegate json_encode_bool(args), to: DispatchJson, as: :encode_bool
  defdelegate json_encode_null(args), to: DispatchJson, as: :encode_null
  defdelegate json_encode_list(args), to: DispatchJson, as: :encode_list
  defdelegate json_encode_float(args), to: DispatchJson, as: :encode_float
  defdelegate json_encode_encode(args), to: DispatchJson, as: :encode_encode
  defdelegate json_encode_dict(args), to: DispatchJson, as: :encode_dict

  # Effects / subscriptions
  defdelegate events_batch(args), to: Effects
  defdelegate light_enable(args), to: Effects
  defdelegate light_disable(args), to: Effects
  defdelegate light_interaction(args), to: Effects
  defdelegate platform_application(args), to: Effects
  defdelegate platform_watchface(args), to: Effects
  defdelegate vibes_short_pulse(args), to: Effects
  defdelegate vibes_long_pulse(args), to: Effects
  defdelegate vibes_double_pulse(args), to: Effects
  defdelegate vibes_pattern_cmd(args), to: Effects
  defdelegate vibes_cancel(args), to: Effects
  defdelegate speaker_play_tone_cmd(args), to: Effects
  defdelegate speaker_play_notes_cmd(args), to: Effects
  defdelegate speaker_play_tracks_cmd(args), to: Effects
  defdelegate speaker_stop_cmd(args), to: Effects
  defdelegate speaker_set_volume_cmd(args), to: Effects
  defdelegate speaker_stream_open_cmd(args), to: Effects
  defdelegate speaker_stream_write_cmd(args), to: Effects
  defdelegate speaker_stream_close_cmd(args), to: Effects
  defdelegate dictation_start(args), to: Effects
  defdelegate dictation_stop(args), to: Effects
  defdelegate backlight_cmd(args), to: Effects
  defdelegate frame_every_cmd(args), to: Effects
  defdelegate frame_at_fps_cmd(args), to: Effects
  defdelegate unobstructed_current_bounds_cmd(args), to: Effects
  defdelegate compass_peek_cmd(args), to: Effects

  # Storage / datalog
  defdelegate datalog_tag_value(args), to: Storage
  defdelegate datalog_log_int32_cmd(args), to: Storage
  defdelegate datalog_log_bytes_cmd(args), to: Storage
  defdelegate storage_read_int_cmd(args), to: Storage, as: :read_int_cmd
  defdelegate storage_read_string_cmd(args), to: Storage, as: :read_string_cmd
  defdelegate storage_write_int_cmd(args), to: Storage, as: :write_int_cmd
  defdelegate storage_write_string_cmd(args), to: Storage, as: :write_string_cmd
  defdelegate storage_delete_cmd(args), to: Storage, as: :delete_cmd
  defdelegate storage_read_max_size_cmd(args), to: Storage, as: :read_max_size_cmd

  # Platform / basics
  defdelegate platform_launch_reason(args), to: Platform, as: :launch_reason
  defdelegate platform_display_shape_is_round(args), to: Platform, as: :display_shape_is_round

  defdelegate platform_color_capability_is_color(args),
    to: Platform,
    as: :color_capability_is_color

  defdelegate list_repeat(args), to: Basics
  defdelegate list_cons(args), to: Basics
  defdelegate basics_to_float(args), to: Basics, as: :to_float
  defdelegate basics_floor(args), to: Basics, as: :floor
  defdelegate basics_ceiling(args), to: Basics, as: :ceiling
  defdelegate basics_round(args), to: Basics, as: :round_val
  defdelegate basics_truncate(args), to: Basics, as: :truncate
  defdelegate math_clamp(args), to: Basics
  defdelegate rotation_from_pebble_angle(args), to: Basics
  defdelegate kernel_time_now_millis(args), to: Basics
  defdelegate collision_rect_rect(args), to: Basics

  @spec ui_line(Types.registry_args()) :: Types.ui_node()
  def ui_line([x1, y1, x2, y2, color]) when is_integer(x1),
    do: apply(Elmx.Runtime.Pebble.Ui, :line, [%{x: x1, y: y1}, %{x: x2, y: y2}, color])

  def ui_line(args), do: apply(Elmx.Runtime.Pebble.Ui, :line, args)

  @spec ui_context_setting(String.t(), Types.registry_args()) :: Types.ui_node()
  def ui_context_setting(key, [value]), do: Elmx.Runtime.Pebble.Ui.context_setting(key, value)
  def ui_context_setting(key, []), do: Elmx.Runtime.Pebble.Ui.context_setting(key, 0)
  def ui_context_setting(key, args), do: Elmx.Runtime.Pebble.Ui.context_setting(key, List.first(args))

  @spec timer_after_cmd(Types.registry_args()) :: Types.wire_cmd()
  def timer_after_cmd([ms, message]) when is_integer(ms), do: Cmd.timer_after(ms, message)
  def timer_after_cmd([ms | rest]) when is_integer(ms), do: Cmd.timer_after(ms, List.first(rest))
  def timer_after_cmd(_), do: Cmd.none()

  @spec random_generate_cmd(Types.registry_args()) :: Types.wire_cmd()
  def random_generate_cmd([to_msg, generator]) do
    Cmd.device("random", to_msg, Core.random_int(generator))
  end

  def random_generate_cmd(_), do: Cmd.none()

  @spec subscription_call(Types.registry_args()) :: Types.wire_cmd()
  def subscription_call([target | args]) when is_binary(target),
    do: subscription_cmd(target, args)

  def subscription_call(_), do: Cmd.none()

  @spec subscription_cmd(String.t(), Types.registry_args()) :: Types.wire_cmd()
  def subscription_cmd(target, args) when is_binary(target) do
    callback =
      case args do
        [] -> "Tick"
        [cb] -> cb
        args -> List.last(args)
      end

    Cmd.subscription_register(target, callback: callback)
  end

  @spec device_stub(String.t(), Types.registry_args()) :: Types.wire_cmd()
  def device_stub(kind, args) when is_binary(kind), do: DeviceStubs.device(kind, args)

  @spec health_device_cmd(String.t(), Types.registry_args()) :: Types.wire_cmd()
  defdelegate health_device_cmd(kind, args), to: Platform

  defdelegate kernel_runtime_function?(name), to: Kernel
  defdelegate kernel_runtime_stub(function, args), to: Kernel
end
