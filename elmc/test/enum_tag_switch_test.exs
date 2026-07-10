defmodule Elmc.EnumTagSwitchTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Lower.Case.TagSwitch
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.Backend.Plan.Context

  test "tag switch peels enum call subject to native int before switch" do
    decl_map = %{
      {"Corner", "pickCorner"} => %{
        name: "pickCorner",
        args: ["model"],
        type: "Model -> Corner",
        expr: %{op: :int_literal, value: 0}
      }
    }

    subject = %{
      op: :qualified_call,
      target: "Corner.pickCorner",
      args: [%{op: :var, name: "model"}]
    }

    branches = [
      %{
        pattern: %{kind: :constructor, name: "Alpha", tag: 1, arg_pattern: nil},
        expr: %{op: :int_literal, value: 10}
      },
      %{
        pattern: %{kind: :constructor, name: "Beta", tag: 2, arg_pattern: nil},
        expr: %{op: :int_literal, value: 20}
      },
      %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
    ]

    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_enum_types, MapSet.new(["Corner"]))
    Process.put(:elmc_constructor_tags, %{"Alpha" => 1, "Beta" => 2})
    Process.put(:elmc_codegen_opts, %{codegen_profile: :size, enum_tag_peel: true, plan_ir_mode: :primary})

    ctx = Context.new(module: "Main", params: ["model"], decl_map: decl_map)
    b0 = Builder.new("Main", "labelCorner", args: ["model"], rc_required: true)

    assert {:ok, _reg, b1} = TagSwitch.compile(subject, branches, ctx, b0)

    peeled? =
      b1.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.any?(&(&1.op == :boxed_tag_peel))

    assert peeled?

    case_decl = %{
      name: "labelCorner",
      args: ["model"],
      expr: %{op: :case, subject: subject, branches: branches}
    }

    full_decl_map = Map.put(decl_map, {"Main", "labelCorner"}, case_decl)

    case PlanLower.lower(case_decl, "Main", full_decl_map, rc_required: true) do
      {:ok, plan} ->
        c = CLowerFunction.emit(plan)
        assert c =~ "switch ("
        assert c =~ "elmc_as_int("

      :unsupported ->
        :ok
    end
  end
end
