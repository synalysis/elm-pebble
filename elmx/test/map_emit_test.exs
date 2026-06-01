defmodule Elmx.MapEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Runtime.Core

  defp base_env do
    Emit.function_env("Main", [])
    |> Map.put(:module, "Main")
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:function_arities, %{})
  end

  test "List.map emits Core.map" do
    expr = %{
      op: :qualified_call,
      target: "List.map",
      args: [
        %{
          op: :lambda,
          args: ["x"],
          body: %{
            op: :call,
            name: "__mul__",
            args: [%{op: :var, name: "x"}, %{op: :int_literal, value: 2}]
          }
        },
        %{op: :list_literal, items: [%{op: :int_literal, value: 3}]}
      ]
    }

    {code, _, _} = Emit.compile_expr(expr, base_env(), 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "Elmx.Runtime.Core.map"
    refute source =~ "Enum.map"
  end

  test "Core.map applies unary and partially applied callbacks" do
    assert Core.map(fn x -> x * 2 end, [1, 2]) == [2, 4]

    partial = fn offset -> fn item -> offset + item end end
    assert Core.map(partial.(5), [1, 2]) == [6, 7]
  end

  test "Core.filter_map handles Maybe results" do
    fun = fn x -> if x > 0, do: {:Just, x}, else: :Nothing end
    assert Core.filter_map(fun, [-1, 2, 0, 3]) == [2, 3]
  end
end
