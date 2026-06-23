defmodule Elmx.Runtime.Pebble.Dispatch.Kernel do
  @moduledoc false

  alias Elmx.Runtime.Http
  alias Elmx.Runtime.Pebble.Dispatch
  alias Elmx.Types

  @spec kernel_runtime_function?(String.t()) :: boolean()
  def kernel_runtime_function?(name) when is_binary(name) do
    String.starts_with?(name, "elmx_kernel_pebble_watch_") or
      String.starts_with?(name, "elmx_kernel_pebble_phone_")
  end

  @spec kernel_runtime_stub(String.t(), Types.registry_args()) :: Types.runtime_dispatch_result()
  def kernel_runtime_stub(function, args) do
    case function do
      "elmx_kernel_pebble_watch_get_current_time_string" ->
        Dispatch.device_stub("current_time_string", args)

      "elmx_kernel_pebble_watch_get_current_date_time" ->
        Dispatch.device_stub("current_date_time", args)

      "elmx_kernel_pebble_watch_get_battery_level" ->
        Dispatch.device_stub("battery_level", args)

      "elmx_kernel_pebble_watch_get_connection_status" ->
        Dispatch.device_stub("connection_status", args)

      "elmx_kernel_pebble_watch_get_clock_style_24h" ->
        Dispatch.device_stub("clock_style_24h", args)

      "elmx_kernel_pebble_watch_get_timezone_is_set" ->
        Dispatch.device_stub("timezone_is_set", args)

      "elmx_kernel_pebble_watch_get_timezone" ->
        Dispatch.device_stub("timezone", args)

      "elmx_kernel_pebble_watch_get_watch_model" ->
        Dispatch.device_stub("watch_model", args)

      "elmx_kernel_pebble_watch_get_color" ->
        Dispatch.device_stub("watch_color", args)

      "elmx_kernel_pebble_watch_get_firmware_version" ->
        Dispatch.device_stub("firmware_version", args)

      "elmx_kernel_pebble_watch_storage_read_string" ->
        Dispatch.storage_read_string_cmd(args)

      "elmx_kernel_pebble_watch_storage_read_int" ->
        Dispatch.storage_read_int_cmd(args)

      "elmx_kernel_pebble_watch_storage_write_int" ->
        Dispatch.storage_write_int_cmd(args)

      "elmx_kernel_pebble_watch_storage_write_string" ->
        Dispatch.storage_write_string_cmd(args)

      "elmx_kernel_pebble_watch_storage_delete" ->
        Dispatch.storage_delete_cmd(args)

      "elmx_kernel_pebble_watch_storage_read_max_size" ->
        Dispatch.storage_read_max_size_cmd(args)

      "elmx_kernel_pebble_watch_speaker_is_muted" ->
        Dispatch.device_stub("speaker_is_muted", args)

      "elmx_kernel_pebble_watch_speaker_get_status" ->
        Dispatch.device_stub("speaker_status", args)

      "elmx_kernel_pebble_watch_health_supported" ->
        Dispatch.health_device_cmd("health_supported", args)

      "elmx_kernel_pebble_watch_health_value" ->
        Dispatch.health_device_cmd("health_value", args)

      "elmx_kernel_pebble_watch_health_sum_today" ->
        Dispatch.health_device_cmd("health_sum_today", args)

      "elmx_kernel_pebble_watch_health_sum" ->
        Dispatch.health_device_cmd("health_sum", args)

      "elmx_kernel_pebble_watch_health_accessible" ->
        Dispatch.health_device_cmd("health_accessible", args)

      "elmx_kernel_pebble_watch_compass_current" ->
        Dispatch.compass_peek_cmd(args)

      "elmx_kernel_pebble_phone_http_get" ->
        Http.get(args)

      "elmx_kernel_pebble_phone_http_post" ->
        Http.post(args)

      "elmx_kernel_pebble_phone_http_request" ->
        Http.request(args)

      "elmx_kernel_pebble_phone_http_expect_string" ->
        Http.expect_string(args)

      "elmx_kernel_pebble_phone_http_expect_json" ->
        Http.expect_json(args)

      _ ->
        Elmx.Runtime.Cmd.none()
    end
  end
end
