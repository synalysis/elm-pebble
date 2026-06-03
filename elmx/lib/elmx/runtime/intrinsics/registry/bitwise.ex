defmodule Elmx.Runtime.Intrinsics.Registry.Bitwise do
  @moduledoc false

  alias Elmx.Runtime.Core.Bitwise
  alias Elmx.Runtime.Handler

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmc_bitwise_and" => {Bitwise, :and_},
      "elmc_bitwise_or" => {Bitwise, :or_},
      "elmc_bitwise_xor" => {Bitwise, :xor},
      "elmc_bitwise_complement" => {Bitwise, :complement},
      "elmc_bitwise_shift_left_by" => {Bitwise, :shift_left_by},
      "elmc_bitwise_shift_right_by" => {Bitwise, :shift_right_by},
      "elmc_bitwise_shift_right_zf_by" => {Bitwise, :shift_right_zf_by}
    }
  end
end
