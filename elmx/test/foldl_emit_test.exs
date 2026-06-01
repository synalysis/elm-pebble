defmodule Elmx.FoldlEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Runtime.Core

  defp base_env do
    Emit.function_env("Main", [])
    |> Map.put(:module, "Main")
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:function_arities, %{})
  end

  test "List.foldl emits Core.foldl" do
    expr = %{
      op: :qualified_call,
      target: "List.foldl",
      args: [
        %{
          op: :lambda,
          args: ["x"],
          body: %{
            op: :lambda,
            args: ["acc"],
            body: %{
              op: :call,
              name: "__add__",
              args: [%{op: :var, name: "x"}, %{op: :var, name: "acc"}]
            }
          }
        },
        %{op: :int_literal, value: 0},
        %{op: :list_literal, items: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}]}
      ]
    }

    {code, _, _} = Emit.compile_expr(expr, base_env(), 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "Elmx.Runtime.Core.foldl"
    refute source =~ "Enum.reduce"
  end

  test "Core.foldl applies curried two-arg lambdas" do
    fun = fn x -> fn acc -> x + acc end end
    assert Core.foldl(fun, 0, [1, 2, 3]) == 6
  end

  test "Core.apply2 applies two-arity functions" do
    assert Core.apply2(fn a, b -> a + b end, 2, 3) == 5
  end
end
