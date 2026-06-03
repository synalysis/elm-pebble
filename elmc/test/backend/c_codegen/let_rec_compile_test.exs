defmodule Elmc.Backend.CCodegen.LetRecCompileTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.LetCompile
  alias Elmc.Backend.CCodegen.LetRecCompile

  test "cyclic_bindings? detects mutual references" do
    bindings = [
      {"f", %{op: :var, name: "g"}},
      {"g", %{op: :var, name: "f"}}
    ]

    assert LetRecCompile.cyclic_bindings?(bindings)
  end

  test "compile emits forward refs for cyclic let groups" do
  expr = %{
      op: :let_in,
      name: "f",
      value_expr: %{op: :lambda, args: ["x"], body: %{op: :var, name: "g"}},
      in_expr: %{
        op: :let_in,
        name: "g",
        value_expr: %{op: :lambda, args: ["y"], body: %{op: :var, name: "f"}},
        in_expr: %{op: :var, name: "f"}
      }
    }

    {code, _var, _} = LetCompile.compile(expr, %{__module__: "Main"}, 0)

    assert code =~ "elmc_forward_ref_new"
    assert code =~ "elmc_forward_ref_set"
    assert code =~ "elmc_forward_ref_get"
    assert code =~ "elmc_forward_ref_capture"
  end
end
