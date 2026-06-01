defmodule Elmx.Runtime.Core.Bitwise do
  @moduledoc false

  @mask64 0xFFFFFFFFFFFFFFFF

  @spec and_(integer(), integer()) :: integer()
  def and_(left, right), do: :erlang.band(left, right)

  @spec or_(integer(), integer()) :: integer()
  def or_(left, right), do: :erlang.bor(left, right)

  @spec xor(integer(), integer()) :: integer()
  def xor(left, right), do: :erlang.bxor(left, right)

  @spec complement(integer()) :: integer()
  def complement(value), do: :erlang.bnot(value)

  @spec shift_left_by(integer(), integer()) :: integer()
  def shift_left_by(bits, value), do: :erlang.bsl(value, clamp_shift(bits))

  @spec shift_right_by(integer(), integer()) :: integer()
  def shift_right_by(bits, value), do: :erlang.bsr(value, clamp_shift(bits))

  @spec shift_right_zf_by(integer(), integer()) :: integer()
  def shift_right_zf_by(bits, value) do
    raw = :erlang.band(value, @mask64)
    :erlang.bsr(raw, clamp_shift(bits))
  end

  defp clamp_shift(bits) when bits < 0, do: 0
  defp clamp_shift(bits), do: bits
end
