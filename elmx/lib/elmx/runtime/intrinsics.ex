defmodule Elmx.Runtime.Intrinsics do
  @moduledoc """
  Registry and dispatch for `elmc_*` runtime intrinsics emitted by `elmc` codegen.
  """

  alias Elmx.Runtime.Intrinsics.Registry

  @handlers Registry.handlers()

  @spec symbols() :: [String.t()]
  def symbols, do: Map.keys(@handlers) |> Enum.sort()

  @spec known?(String.t()) :: boolean()
  def known?(name) when is_binary(name), do: Map.has_key?(@handlers, name)

  @spec compile_call(String.t(), [iodata()]) :: {:ok, String.t()} | :error
  def compile_call(name, arg_codes) when is_binary(name) and is_list(arg_codes) do
    case Map.get(@handlers, name) do
      nil -> :error
      handler -> {:ok, compile_handler(handler, arg_codes)}
    end
  end

  @spec apply(String.t(), list()) :: {:ok, term()} | :error
  def apply(name, args) when is_binary(name) and is_list(args) do
    case Map.get(@handlers, name) do
      nil ->
        :error

      handler ->
        {:ok, apply_handler(handler, args)}
    end
  end

  defp compile_handler({mod, fun}, arg_codes) do
    args = Enum.map(arg_codes, &IO.iodata_to_binary/1)
    "#{module_ref(mod)}.#{fun}(#{Enum.join(args, ", ")})"
  end

  defp compile_handler({mod, fun, opts}, arg_codes) do
    args = reorder(arg_codes, opts[:args]) |> Enum.map(&IO.iodata_to_binary/1)
    "#{module_ref(mod)}.#{fun}(#{Enum.join(args, ", ")})"
  end

  defp module_ref(mod) when is_atom(mod), do: mod |> Module.split() |> Enum.join(".")

  defp apply_handler({mod, fun}, args), do: apply(mod, fun, args)

  defp apply_handler({mod, fun, opts}, args) do
    apply(mod, fun, reorder(args, opts[:args]))
  end

  defp reorder(items, nil), do: items

  defp reorder(items, order) when is_list(order) do
    Enum.map(order, &Enum.at(items, &1))
  end
end
