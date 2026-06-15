defmodule Elmx.Runtime.Intrinsics.Registry.Char do
  @moduledoc false

  alias Elmx.Runtime.Core.Chars
  alias Elmx.Runtime.Handler

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmc_char_to_code" => {Chars, :to_code},
      "elmc_char_to_lower" => {Chars, :to_lower},
      "elmc_char_to_upper" => {Chars, :to_upper},
      "elmc_char_is_digit" => {Chars, :is_digit},
      "elmc_char_is_hex_digit" => {Chars, :is_hex_digit},
      "elmc_char_is_oct_digit" => {Chars, :is_oct_digit},
      "elmc_char_is_lower" => {Chars, :is_lower},
      "elmc_char_is_upper" => {Chars, :is_upper},
      "elmc_char_is_alpha" => {Chars, :is_alpha},
      "elmc_char_is_alpha_num" => {Chars, :is_alpha_num}
    }
  end
end
