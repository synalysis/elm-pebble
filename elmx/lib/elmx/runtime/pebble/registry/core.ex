defmodule Elmx.Runtime.Pebble.Registry.Core do
  @moduledoc false

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Core.MaybeResult
  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Pebble.Dispatch

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmx_core_maybe_with_default" => {MaybeResult, :maybe_with_default},
      "elmx_core_maybe_map" => {MaybeResult, :maybe_map},
      "elmx_core_maybe_and_then" => {MaybeResult, :maybe_and_then},
      "elmx_core_maybe_map2" => {MaybeResult, :maybe_map2, args: [1, 2, 0]},
      "elmx_core_result_map" => {MaybeResult, :result_map},
      "elmx_core_result_map_error" => {MaybeResult, :result_map_error},
      "elmx_core_result_with_default" => {MaybeResult, :result_with_default},
      "elmx_core_result_and_then" => {MaybeResult, :result_and_then},
      "elmx_core_random_generator" => {MaybeResult, :random_generator},
      "elmx_basics_compare" => {Core, :basics_compare},
      "elmx_list_repeat" => {Dispatch, :list_repeat},
      "elmx_core_list_repeat" => {Dispatch, :list_repeat},
      "elmx_list_cons" => {Dispatch, :list_cons},
      "elmx_math_clamp" => {Dispatch, :math_clamp},
      "elmx_basics_to_float" => {Dispatch, :basics_to_float},
      "elmx_basics_floor" => {Dispatch, :basics_floor},
      "elmx_basics_ceiling" => {Dispatch, :basics_ceiling},
      "elmx_basics_round" => {Dispatch, :basics_round},
      "elmx_basics_truncate" => {Dispatch, :basics_truncate}
    }
  end
end
