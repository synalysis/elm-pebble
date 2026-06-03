defmodule Elmx.Runtime.Generator do
  @moduledoc """
  Elixir runtime parity surface for `elmc` `Runtime.Generator` intrinsics.

  Codegen emits `elmc_*` `runtime_call` nodes; this module maps every symbol
  referenced from `elmc` `c_codegen` to `Elmx.Runtime.*` implementations.
  `elmx_*` symbols are resolved via `Elmx.Runtime.Pebble.Registry`.

  Both registries compile and invoke through `Elmx.Runtime.Handler` and
  `Elmx.Runtime.CodegenRefs` module paths. Qualified Elm stdlib calls use
  `Elmx.Runtime.Stdlib` instead (see `Emit.Qualified` and `Stdlib.Qualified`).
  """

  alias Elmx.Runtime.Intrinsics
  alias Elmx.Runtime.Pebble.Registry, as: PebbleRegistry
  alias Elmx.Types

  @spec symbols() :: [String.t()]
  def symbols do
    (Intrinsics.symbols() ++ PebbleRegistry.symbols())
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec known?(String.t()) :: boolean()
  def known?(name) when is_binary(name),
    do: Intrinsics.known?(name) or PebbleRegistry.known?(name)

  @spec compile_call(String.t(), [iodata()]) :: {:ok, String.t()} | :error
  def compile_call(name, arg_codes) when is_binary(name) and is_list(arg_codes) do
    case Intrinsics.compile_call(name, arg_codes) do
      {:ok, _} = ok ->
        ok

      :error ->
        PebbleRegistry.compile_call(name, arg_codes)
    end
  end

  @spec apply(String.t(), Types.registry_args()) :: {:ok, Types.runtime_dispatch_result()} | :error
  def apply(name, args) when is_binary(name) and is_list(args) do
    cond do
      String.starts_with?(name, "elmx_") ->
        {:ok, PebbleRegistry.apply(name, args)}

      true ->
        Intrinsics.apply(name, args)
    end
  end
end
