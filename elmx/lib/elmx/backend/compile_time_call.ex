defmodule Elmx.Backend.CompileTimeCall do
  @moduledoc false

  alias Elmx.Backend.QualifiedRewrite
  alias Elmx.Runtime.Pebble

  @max_dummy_args 4

  @doc """
  True when `qualified_call` to `target` is lowered during codegen (runtime/special rewrite),
  not via emitted Elm function bodies.
  """
  @spec handled?(String.t()) :: boolean()
  def handled?(target) when is_binary(target) do
    qualified_rewrite?(target) or pebble_rewrite_handled?(target)
  end

  @spec emit_function?(String.t(), String.t(), MapSet.t(), keyword()) :: boolean()
  def emit_function?(module, name, reachable, opts)
      when is_binary(module) and is_binary(name) do
    key = "#{module}.#{name}"

    if not MapSet.member?(reachable, key) do
      false
    else
      cond do
        not Keyword.has_key?(opts, :user_module_names) ->
          true

        module in Keyword.get(opts, :user_module_names, []) ->
          true

        module == "Pebble.Ui" ->
          not handled?(key)

        true ->
          false
      end
    end
  end

  defp qualified_rewrite?(target) do
    Enum.any?(0..@max_dummy_args, fn n ->
      match?({:ok, _}, QualifiedRewrite.rewrite(target, dummy_args(n)))
    end)
  end

  # Subscription stubs rewrite to `0` only for arity-0 probes; do not treat that as
  # "handled" or companion-core callback bodies are never emitted.
  defp pebble_rewrite_handled?(target) do
    case Pebble.rewrite_qualified_call(target, []) do
      {:ok, %{op: :int_literal, value: 0}} ->
        false

      {:ok, _} ->
        true

      _ ->
        Enum.any?(1..@max_dummy_args, fn n ->
          match?({:ok, _}, Pebble.rewrite_qualified_call(target, dummy_args(n)))
        end)
    end
  end

  defp dummy_args(n) when n >= 0 do
    Enum.map(1..n//1, fn _ -> %{op: :int_literal, value: 0} end)
  end
end
