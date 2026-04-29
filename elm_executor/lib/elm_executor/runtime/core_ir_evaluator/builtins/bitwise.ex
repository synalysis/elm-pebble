defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Bitwise do
  @moduledoc false

  @spec eval(String.t(), term()) :: {:ok, term()} | :no_builtin
  def eval("and", [a, b]) when is_integer(a) and is_integer(b), do: {:ok, Bitwise.band(a, b)}
  def eval("or", [a, b]) when is_integer(a) and is_integer(b), do: {:ok, Bitwise.bor(a, b)}
  def eval("xor", [a, b]) when is_integer(a) and is_integer(b), do: {:ok, Bitwise.bxor(a, b)}
  def eval("complement", [a]) when is_integer(a), do: {:ok, Bitwise.bnot(a)}

  def eval("and", [a, b]) when is_number(a) and is_number(b),
    do: {:ok, Bitwise.band(trunc(a), trunc(b))}

  def eval("or", [a, b]) when is_number(a) and is_number(b),
    do: {:ok, Bitwise.bor(trunc(a), trunc(b))}

  def eval("xor", [a, b]) when is_number(a) and is_number(b),
    do: {:ok, Bitwise.bxor(trunc(a), trunc(b))}

  def eval("complement", [a]) when is_number(a), do: {:ok, Bitwise.bnot(trunc(a))}

  def eval("shiftleftby", [offset, value])
      when is_integer(offset) and is_integer(value) and offset >= 0,
      do: {:ok, Bitwise.bsl(value, offset)}

  def eval("shiftleftby", [offset, value]) when is_number(offset) and is_number(value) do
    o = trunc(offset)
    v = trunc(value)
    if o >= 0, do: {:ok, Bitwise.bsl(v, o)}, else: {:ok, Bitwise.bsr(v, -o)}
  end

  def eval("shiftrightby", [offset, value])
      when is_integer(offset) and is_integer(value) and offset >= 0,
      do: {:ok, Bitwise.bsr(value, offset)}

  def eval("shiftrightby", [offset, value]) when is_number(offset) and is_number(value) do
    o = trunc(offset)
    v = trunc(value)
    if o >= 0, do: {:ok, Bitwise.bsr(v, o)}, else: {:ok, Bitwise.bsl(v, -o)}
  end

  def eval("shiftrightzfby", [offset, value])
      when is_integer(offset) and is_integer(value) and offset >= 0 do
    shifted =
      value
      |> Bitwise.band(0xFFFFFFFF)
      |> Bitwise.bsr(offset)

    {:ok, shifted}
  end

  def eval("shiftrightzfby", [offset, value]) when is_number(offset) and is_number(value) do
    o = trunc(offset)
    v = trunc(value)

    if o >= 0 do
      shifted = v |> Bitwise.band(0xFFFFFFFF) |> Bitwise.bsr(o)
      {:ok, shifted}
    else
      {:ok, Bitwise.bsl(v, -o)}
    end
  end

  def eval(_function_name, _values), do: :no_builtin
end
