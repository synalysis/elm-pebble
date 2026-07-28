defmodule Elmc.PlanDeepConsListIntTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower

  test "List Int deep cons + wildcard uses length check and nth peels" do
    cons = fn head, tail ->
      %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}
    end

    # a :: b :: c :: d :: _
    pattern =
      cons.(
        %{kind: :var, name: "a"},
        cons.(
          %{kind: :var, name: "b"},
          cons.(
            %{kind: :var, name: "c"},
            cons.(%{kind: :var, name: "d"}, %{kind: :wildcard})
          )
        )
      )

    decl = %{
      name: "takeFour",
      args: ["xs"],
      type: "List Int -> Int",
      ownership: [:borrow_arg, :borrow_result],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "xs"},
        branches: [
          %{pattern: pattern, expr: %{op: :var, name: "a"}},
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    Process.put(:elmc_program_decls, %{{"Main", "takeFour"} => decl})
    Process.put(:elmc_codegen_opts, %{plan_ir_mode: :primary})
    on_exit(fn -> Process.delete(:elmc_program_decls) end)
    on_exit(fn -> Process.delete(:elmc_codegen_opts) end)

    assert {:ok, plan} =
             PlanLower.lower(decl, "Main", %{{"Main", "takeFour"} => decl}, rc_required: true)

    c = CLowerFunction.emit(plan)

    assert c =~ "elmc_list_length_native"
    assert c =~ "elmc_list_nth_int_default"
    refute c =~ "elmc_list_head("
    refute c =~ "elmc_maybe_just_payload"
    assert length(Regex.scan(~r/elmc_list_nth_int_default\(xs, \d+, 0\)/, c)) >= 4
  end
end
