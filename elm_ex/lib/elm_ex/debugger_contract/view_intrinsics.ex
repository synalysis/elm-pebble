defmodule ElmEx.DebuggerContract.ViewIntrinsics do
  @moduledoc false

  @int_call_names ~w(
    __idiv__ __fdiv__ __mul__ __sub__ __add__ __pow__
    modBy remainderBy max min abs negate round clamp clampInt
    Basics.modBy Basics.remainderBy Basics.abs Basics.negate Basics.round
    basics.modby basics.remainderby
  )

  @intrinsic_operator_names ~w(
    __add__ __sub__ __mul__ __fdiv__ __idiv__ __pow__
  )

  @spec int_call_name?(String.t()) :: boolean()
  def int_call_name?(name) when is_binary(name), do: name in @int_call_names
  def int_call_name?(_), do: false

  @spec intrinsic_operator?(String.t()) :: boolean()
  def intrinsic_operator?(name) when is_binary(name), do: name in @intrinsic_operator_names
  def intrinsic_operator?(_), do: false
end
