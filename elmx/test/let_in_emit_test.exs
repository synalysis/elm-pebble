defmodule Elmx.LetInEmitTest do
  use ExUnit.Case, async: true

  alias Elmx.Backend.ElixirCodegen.Emit

  defp env do
    Emit.function_env("Main", [])
    |> Map.put(:module, "Main")
    |> Map.put(:function_arities, %{})
    |> Map.put(:zero_arity_fns, MapSet.new())
    |> Map.put(:constructor_lookup, %{})
  end

  test "nested let_in emits IIFE so inner value sees outer binding" do
    inner =
      %{
        op: :let_in,
        name: "g",
        value_expr: %{op: :lambda, args: ["x"], body: %{op: :var, name: "x"}},
        in_expr: %{op: :var, name: "f"}
      }

    outer =
      %{
        op: :let_in,
        name: "f",
        value_expr: %{op: :lambda, args: ["x"], body: %{op: :var, name: "x"}},
        in_expr: inner
      }

    {code, _, _} = Emit.compile_expr(outer, env(), 0)
    source = IO.iodata_to_binary(code)

    assert source =~ "(fn ->"
    assert source =~ "f = "
    assert source =~ "g = "
    assert source =~ "end).()"
  end
end
