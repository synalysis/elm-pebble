defmodule Elmx.IndexedMapEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Runtime.Core

  defp base_env do
    Emit.function_env("Main", [])
    |> Map.put(:module, "Main")
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:function_arities, %{})
  end

  test "List.indexedMap emits Core.indexed_map" do
    expr = %{
      op: :qualified_call,
      target: "List.indexedMap",
      args: [
        %{
          op: :lambda,
          args: ["i"],
          body: %{
            op: :lambda,
            args: ["v"],
            body: %{
              op: :call,
              name: "__add__",
              args: [%{op: :var, name: "i"}, %{op: :var, name: "v"}]
            }
          }
        },
        %{op: :list_literal, items: [%{op: :int_literal, value: 10}]}
      ]
    }

    {code, _, _} = Emit.compile_expr(expr, base_env(), 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "Elmx.Runtime.Core.indexed_map"
    refute source =~ "Enum.with_index"
  end

  test "Core.indexed_map applies curried two-arg lambdas" do
    fun = fn i -> fn v -> i + v end end
    assert Core.indexed_map(fun, [10, 20]) == [10, 21]
  end

  test "Core.indexed_map applies two-arity functions" do
    fun = fn i, v -> i + v end
    assert Core.indexed_map(fun, [10, 20]) == [10, 21]
  end
end
