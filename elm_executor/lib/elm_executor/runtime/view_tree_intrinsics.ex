defmodule ElmExecutor.Runtime.ViewTreeIntrinsics do
  @moduledoc false

  # Integer operators the parser-shaped view tree evaluator can lower without Core IR.
  # Kept aligned with ElmEx.IR.Validation intrinsic arithmetic names plus common Basics aliases.
  @int_call_names ~w(
    __idiv__ __fdiv__ __mul__ __sub__ __add__ __pow__
    modBy remainderBy max min abs negate round clamp clampInt
    Basics.modBy Basics.remainderBy Basics.abs Basics.negate Basics.round
    basics.modby basics.remainderby
  )a

  @intrinsic_operator_names ~w(
    __add__ __sub__ __mul__ __fdiv__ __idiv__ __pow__
  )a

  @spec int_call_names() :: [atom()]
  def int_call_names, do: @int_call_names

  @spec int_call_name?(String.t()) :: boolean()
  def int_call_name?(name) when is_binary(name), do: name in @int_call_names

  def int_call_name?(_), do: false

  @spec intrinsic_operator_names() :: [atom()]
  def intrinsic_operator_names, do: @intrinsic_operator_names

  @spec intrinsic_operator?(String.t()) :: boolean()
  def intrinsic_operator?(name) when is_binary(name), do: name in @intrinsic_operator_names

  def intrinsic_operator?(_), do: false
end
