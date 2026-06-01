defmodule Elmx.UserPartialEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit

  defp env do
    Emit.function_env("Main", [])
    |> Map.put(:module, "Main")
    |> Map.put(:function_arities, %{"add2" => 2, "triple" => 3})
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:constructor_lookup, %{})
    |> Map.put(:cross_module_arities, %{})
    |> Map.put(:emit_module_names, ["Main"])
  end

  test "partial user call with one fixed arg emits capture" do
    expr = %{op: :call, name: "add2", args: [%{op: :int_literal, value: 1}]}

    {code, _, _} = Emit.compile_expr(expr, env(), 0)
    source = IO.iodata_to_binary(code)

    assert source == "&elmx_fn_Main_add2(1, &1)"
  end

  test "partial user call with two fixed args emits one remaining capture" do
    expr = %{
      op: :call,
      name: "triple",
      args: [%{op: :int_literal, value: 1}, %{op: :int_literal, value: 2}]
    }

    {code, _, _} = Emit.compile_expr(expr, env(), 0)
    source = IO.iodata_to_binary(code)

    assert source == "&elmx_fn_Main_triple(1, 2, &1)"
  end
end
