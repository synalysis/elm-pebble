defmodule Elmx.Runtime.Intrinsics.Registry.ElmxCore do
  @moduledoc false

  alias Elmx.Runtime.Core.MaybeResult
  alias Elmx.Runtime.Core.Task
  alias Elmx.Runtime.Handler

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmx_core_maybe_with_default" => {MaybeResult, :maybe_with_default},
      "elmx_core_maybe_map" => {MaybeResult, :maybe_map},
      "elmx_core_maybe_and_then" => {MaybeResult, :maybe_and_then},
      "elmx_core_maybe_map2" => {MaybeResult, :maybe_map2, args: [1, 2, 0]},
      "elmx_core_maybe_map3" => {MaybeResult, :maybe_map3},
      "elmx_core_maybe_map4" => {MaybeResult, :maybe_map4},
      "elmx_core_maybe_map5" => {MaybeResult, :maybe_map5},
      "elmx_core_result_map" => {MaybeResult, :result_map},
      "elmx_core_result_map2" => {MaybeResult, :result_map2},
      "elmx_core_result_map3" => {MaybeResult, :result_map3},
      "elmx_core_result_map4" => {MaybeResult, :result_map4},
      "elmx_core_result_map5" => {MaybeResult, :result_map5},
      "elmx_core_result_with_default" => {MaybeResult, :result_with_default},
      "elmx_core_result_and_then" => {MaybeResult, :result_and_then},
      "elmx_core_result_map_error" => {MaybeResult, :result_map_error},
      "elmx_core_task_map" => {Task, :map},
      "elmx_core_task_map2" => {Task, :map2, args: [0, 1, 2]},
      "elmx_core_task_map3" => {Task, :map3},
      "elmx_core_task_map4" => {Task, :map4},
      "elmx_core_task_map5" => {Task, :map5},
      "elmx_core_task_sequence" => {Task, :sequence},
      "elmx_core_task_on_error" => {Task, :on_error},
      "elmx_core_task_map_error" => {Task, :map_error},
      "elmx_core_task_attempt" => {Task, :attempt},
      "elmx_core_task_and_then" => {Task, :and_then},
      "elmx_core_random_generator" => {MaybeResult, :random_generator}
    }
  end
end
