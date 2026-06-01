defmodule Elmx.CompareEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit

  test "binary neq call emits !=" do
    expr = %{
      op: :call,
      name: "__neq__",
      args: [%{op: :var, name: "x"}, %{op: :int_literal, value: 0}]
    }

    env =
      Emit.function_env("Main", ["x"])
      |> Map.put(:module, "Main")
      |> Map.put(:x, true)

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    assert IO.iodata_to_binary(code) =~ "!="
    refute IO.iodata_to_binary(code) =~ "__neq__"
  end

  test "partial neq emits unary predicate" do
    expr = %{
      op: :call,
      name: "__neq__",
      args: [%{op: :int_literal, value: 0}]
    }

    env = Emit.function_env("Main", []) |> Map.put(:module, "Main")

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "fn elmx_rhs ->"
    assert source =~ "0 != elmx_rhs"
  end
end
