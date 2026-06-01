defmodule Elmx.Runtime.Generator do
  @moduledoc """
  Elixir runtime parity surface for `elmc` `Runtime.Generator` intrinsics.

  Codegen emits `elmc_*` `runtime_call` nodes; this module maps every symbol
  referenced from `elmc` `c_codegen` to `Elmx.Runtime.*` implementations.
  """

  alias Elmx.Runtime.Intrinsics

  @spec symbols() :: [String.t()]
  def symbols, do: Intrinsics.symbols()

  @spec known?(String.t()) :: boolean()
  def known?(name), do: Intrinsics.known?(name)

  @spec compile_call(String.t(), [iodata()]) :: {:ok, String.t()} | :error
  def compile_call(name, arg_codes), do: Intrinsics.compile_call(name, arg_codes)

  @spec apply(String.t(), list()) :: {:ok, term()} | :error
  def apply(name, args), do: Intrinsics.apply(name, args)
end
