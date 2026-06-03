defmodule Elmx.Runtime.Intrinsics.Registry.Basics do
  @moduledoc false

  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Core.Math
  alias Elmx.Runtime.Handler

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{
      "elmc_basics_abs" => {Core, :basics_abs},
      "elmc_basics_negate" => {Core, :basics_negate},
      "elmc_basics_not" => {Core, :basics_not},
      "elmc_basics_max" => {Core, :basics_max},
      "elmc_basics_min" => {Core, :basics_min},
      "elmc_basics_mod_by" => {Core, :basics_mod_by},
      "elmc_basics_remainder_by" => {Math, :remainder_by},
      "elmc_basics_clamp" => {Core, :basics_clamp},
      "elmc_basics_compare" => {Core, :basics_compare},
      "elmc_basics_xor" => {Math, :xor},
      "elmc_basics_to_float" => {Math, :to_float},
      "elmc_basics_floor" => {Math, :floor},
      "elmc_basics_ceiling" => {Math, :ceiling},
      "elmc_basics_round" => {Math, :round},
      "elmc_basics_truncate" => {Math, :truncate},
      "elmc_basics_sqrt" => {Math, :sqrt},
      "elmc_basics_sin" => {Math, :sin},
      "elmc_basics_cos" => {Math, :cos},
      "elmc_basics_tan" => {Math, :tan},
      "elmc_basics_asin" => {Math, :asin},
      "elmc_basics_acos" => {Math, :acos},
      "elmc_basics_atan" => {Math, :atan},
      "elmc_basics_atan2" => {Math, :atan2},
      "elmc_basics_degrees" => {Math, :degrees},
      "elmc_basics_radians" => {Math, :radians},
      "elmc_basics_turns" => {Math, :turns},
      "elmc_basics_pow" => {Math, :pow},
      "elmc_basics_log_base" => {Math, :log_base},
      "elmc_basics_is_infinite" => {Math, :is_infinite},
      "elmc_basics_is_nan" => {Math, :is_nan},
      "elmc_basics_to_polar" => {Math, :to_polar},
      "elmc_basics_from_polar" => {Math, :from_polar}
    }
  end
end
