defmodule Elmc.GenericReachabilityArithRefsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.GenericReachability

  test "add_vars/sub_vars bare names count as same-module callees" do
    decl_map = %{
      {"Mod", "threshold"} => %{name: "threshold", args: [], expr: %{op: :float_literal, value: 0.001}},
      {"Mod", "use"} => %{
        name: "use",
        args: ["t"],
        expr: %{op: :sub_vars, left: "t", right: "threshold"}
      }
    }

    callees =
      GenericReachability.expr_callees(
        %{op: :sub_vars, left: "t", right: "threshold"},
        "Mod",
        decl_map
      )

    assert {"Mod", "threshold"} in callees
  end
end
