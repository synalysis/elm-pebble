defmodule Elmx.Runtime.Intrinsics do
  @moduledoc """
  Registry and dispatch for `elmc_*` runtime intrinsics emitted by `elmc` codegen.
  """

  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Intrinsics.Registry
  alias Elmx.Types

  @handlers Registry.handlers()

  @spec symbols() :: [String.t()]
  def symbols, do: Map.keys(@handlers) |> Enum.sort()

  @spec known?(String.t()) :: boolean()
  def known?(name) when is_binary(name), do: Map.has_key?(@handlers, name)

  @spec compile_call(String.t(), [iodata()]) :: {:ok, String.t()} | :error
  def compile_call(name, arg_codes) when is_binary(name) and is_list(arg_codes) do
    case Map.get(@handlers, name) do
      nil -> :error
      handler -> {:ok, Handler.compile(handler, arg_codes)}
    end
  end

  @spec apply(String.t(), Types.registry_args()) ::
          {:ok, Types.runtime_dispatch_result()} | :error
  def apply(name, args) when is_binary(name) and is_list(args) do
    case Map.get(@handlers, name) do
      nil ->
        :error

      handler ->
        {:ok, Handler.invoke(handler, args)}
    end
  end
end
