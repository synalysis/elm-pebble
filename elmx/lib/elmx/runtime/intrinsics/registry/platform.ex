defmodule Elmx.Runtime.Intrinsics.Registry.Platform do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.Core.Debug
  alias Elmx.Runtime.Core.Process
  alias Elmx.Runtime.Core.Task
  alias Elmx.Runtime.Core.Time
  alias Elmx.Runtime.Handler

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmc_debug_log" => {Debug, :log},
      "elmc_debug_todo" => {Debug, :todo},
      "elmc_debug_to_string" => {Debug, :to_string},
      "elmc_task_succeed" => {Task, :succeed},
      "elmc_task_fail" => {Task, :fail},
      "elmc_task_map" => {Task, :map},
      "elmc_task_map2" => {Task, :map2, args: [0, 1, 2]},
      "elmc_task_and_then" => {Task, :and_then},
      "elmc_process_spawn" => {Process, :spawn},
      "elmc_process_sleep" => {Process, :sleep},
      "elmc_process_kill" => {Process, :kill},
      "elmc_time_now_millis" => {Time, :now_millis},
      "elmc_time_zone_offset_minutes" => {Time, :zone_offset_minutes},
      "elmc_cmd_backlight_from_maybe" => {Cmd, :backlight_from_maybe}
    }
  end
end
