defmodule Elmx.Runtime.Intrinsics.Registry.MaybeResult do
  @moduledoc false

  alias Elmx.Runtime.Core.MaybeResult
  alias Elmx.Runtime.Handler

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmc_maybe_with_default" => {MaybeResult, :maybe_with_default},
      "elmc_maybe_map" => {MaybeResult, :maybe_map},
      "elmc_maybe_map2" => {MaybeResult, :maybe_map2, args: [1, 2, 0]},
      "elmc_maybe_and_then" => {MaybeResult, :maybe_and_then},
      "elmc_result_map" => {MaybeResult, :result_map},
      "elmc_result_map_error" => {MaybeResult, :result_map_error},
      "elmc_result_and_then" => {MaybeResult, :result_and_then},
      "elmc_result_with_default" => {MaybeResult, :result_with_default},
      "elmc_result_to_maybe" => {MaybeResult, :result_to_maybe},
      "elmc_result_from_maybe" => {MaybeResult, :result_from_maybe}
    }
  end
end
