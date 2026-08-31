defmodule Elmx.Tuple3EmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit

  test "official #3 emits a + nested pair payload" do
    expr = %{
      op: :tuple3,
      a: %{op: :int_literal, value: 1},
      b: %{op: :int_literal, value: 2},
      c: %{op: :int_literal, value: 3}
    }

    env =
      Emit.function_env("Main", [])
      |> Map.put(:module, "Main")
      |> Map.put(:zero_arity_fns, MapSet.new())
      |> Map.put(:function_arities, %{})

    {code, _, _} = Emit.compile_expr(expr, env, 0)
    assert IO.iodata_to_binary(code) == "{1, {2, 3}}"
  end
end
