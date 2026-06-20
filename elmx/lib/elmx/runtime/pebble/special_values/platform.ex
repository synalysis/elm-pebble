defmodule Elmx.Runtime.Pebble.SpecialValues.Platform do
  @moduledoc false

  @behaviour Elmx.Runtime.Pebble.SpecialValues.Dispatcher

  import Elmx.Runtime.Pebble.SpecialValues.Helpers

  alias Elmx.Types

  @spec rewrite(String.t(), Types.ir_arg_list()) :: Types.dispatch_result()
  def rewrite(target, args) when is_binary(target) and is_list(args) do
    case target do
      "Platform.Cmd.batch" -> cmd_batch(args)
      "Pebble.Cmd.batch" -> cmd_batch(args)
      "Platform.Cmd.map" -> cmd_map(args)
      "Pebble.Cmd.map" -> cmd_map(args)
      "Cmd.map" -> cmd_map(args)
      "Platform.Cmd.none" -> {:ok, %{op: :cmd_none}}
      "Pebble.Cmd.none" -> {:ok, %{op: :cmd_none}}
      "Platform.Cmd.getCurrentTimeString" -> ui_call("elmx_time_current_time_string", args)
      "Platform.Cmd.getCurrentDateTime" -> ui_call("elmx_time_current_date_time", args)
      "Platform.Cmd.timerAfter" -> ui_call("elmx_cmd_timer_after", args)
      "Platform.Cmd.storageReadString" -> ui_call("elmx_storage_read_string", args)
      "Platform.Cmd.storageReadInt" -> ui_call("elmx_storage_read_int", args)
      "Platform.Cmd.storageWriteString" -> ui_call("elmx_storage_write_string", args)
      "Platform.Cmd.storageWriteInt" -> ui_call("elmx_storage_write_int", args)
      "Platform.Cmd.storageDelete" -> ui_call("elmx_storage_delete", args)
      "Platform.Cmd.backlight" -> ui_call("elmx_cmd_backlight", args)
      "Platform.Sub.none" -> {:ok, %{op: :int_literal, value: 0}}
      "Platform.Sub.map" -> sub_map(args)
      "Pebble.Sub.map" -> sub_map(args)
      "Sub.map" -> sub_map(args)
      "Platform.worker" -> {:ok, %{op: :int_literal, value: 0}}
      "Platform.application" -> ui_call("elmx_platform_application", args)
      "Platform.Sub.batch" -> subscription_batch(args)
      "Pebble.Platform.launchReasonToInt" -> ui_call("elmx_platform_launch_reason_to_int", args)
      "Pebble.Platform.application" -> ui_call("elmx_platform_application", args)
      "Pebble.Platform.watchface" -> ui_call("elmx_platform_watchface", args)
      "Pebble.Platform.displayShapeIsRound" -> ui_call("elmx_platform_display_shape_is_round", args)
      "Pebble.Platform.colorCapabilityIsColor" -> ui_call("elmx_platform_color_capability_is_color", args)
      "Elm.Kernel.List.cons" when args == [] -> :unmatched
      "Elm.Kernel.List.cons" -> {:ok, %{op: :runtime_call, function: "elmx_list_cons", args: args}}
      _ -> :unmatched
    end
  end
end
