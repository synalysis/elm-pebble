defmodule Elmx.Runtime.Intrinsics.Registry.Tuple do
  @moduledoc false

  alias Elmx.Runtime.Core.Tuple
  alias Elmx.Runtime.Handler

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmc_tuple_first" => {Tuple, :first},
      "elmc_tuple_second" => {Tuple, :second},
      "elmc_tuple_map_first" => {Tuple, :map_first},
      "elmc_tuple_map_second" => {Tuple, :map_second},
      "elmc_tuple_map_both" => {Tuple, :map_both}
    }
  end
end
