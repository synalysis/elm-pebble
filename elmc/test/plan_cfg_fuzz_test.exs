defmodule Elmc.PlanCfgFuzzTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.Lower.Function, as: PlanFunction
  alias Elmc.Backend.Plan.Verify

  @tags %{"Tick" => 1, "GotTime" => 2, "Reset" => 3}

  test "lowered guarded Msg cases verify with reachable CFG (fuzz sample)" do
    Process.put(:elmc_constructor_tags, @tags)
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    for arm_count <- 1..3,
        has_params? <- [false, true] do
      decl = fuzz_update_decl(arm_count, has_params?)
      assert {:ok, plan} = PlanFunction.lower(decl, "Main", %{}, rc_required: true)
      assert :ok = Verify.run(plan)
      refute Enum.any?(plan.blocks, &match?(%{terminator: :none}, &1))

      c = CLowerFunction.emit(plan)

      refute Regex.match?(
               ~r/case 0:\s*__plan_state = -1; break;\s*case 1:/s,
               c
             ),
             "fuzz sample arm_count=#{arm_count} has_params?=#{has_params?} must not halt at entry"
    end
  end

  test "nested case on payload verifies clean" do
    Process.put(:elmc_constructor_tags, @tags)
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "update",
      args: ["msg", "model"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: [
          %{
            pattern: %{kind: :constructor, name: "GotTime", tag: 2, arg_pattern: %{kind: :var, name: "t"}},
            expr: %{
              op: :case,
              subject: %{op: :var, name: "t"},
              branches: [
                %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 42}}
              ]
            }
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
        ]
      }
    }

    assert {:ok, plan} = PlanFunction.lower(decl, "Main", %{}, rc_required: true)
    assert :ok = Verify.run(plan)
  end

  test "tangram-shaped guarded update with param loads does not seal entry" do
    # Same shape as Tangram Main.update / plan_lower_ir_test: Msg case after param loads.
    Process.put(:elmc_constructor_tags, %{"GotTime" => 1, "Tick" => 2, "Reset" => 3})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "update",
      args: ["msg", "model"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: [
          %{
            pattern: %{
              kind: :constructor,
              name: "GotTime",
              tag: 1,
              arg_pattern: %{kind: :var, name: "t"}
            },
            expr: %{op: :var, name: "t"}
          },
          %{
            pattern: %{kind: :constructor, name: "Tick", tag: 2, arg_pattern: nil},
            expr: %{op: :var, name: "model"}
          },
          %{
            pattern: %{kind: :constructor, name: "Reset", tag: 3, arg_pattern: nil},
            expr: %{op: :int_literal, value: 0}
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :var, name: "model"}}
        ]
      }
    }

    assert {:ok, plan} = PlanFunction.lower(decl, "Main", %{}, rc_required: true)
    assert :ok = Verify.run(plan)

    entry = Enum.find(plan.blocks, &(&1.id == plan.entry_block))
    refute match?(:none, entry.terminator), "entry must not halt before Msg tag tests"

    c = CLowerFunction.emit(plan)

    refute Regex.match?(
             ~r/case 0:\s*__plan_state = -1; break;\s*case 1:/s,
             c
           ),
           "tangram-shaped fuzz must not seal entry with -1"
  end

  defp fuzz_update_decl(arm_count, has_params?) do
    ctor_branches =
      for i <- 1..arm_count do
        %{
          pattern: %{
            kind: :constructor,
            name: Enum.at(~w(Tick GotTime Reset), rem(i - 1, 3)),
            tag: i,
            arg_pattern: if(i == 2, do: %{kind: :var, name: "t"}, else: nil)
          },
          expr: %{op: :int_literal, value: i * 10}
        }
      end

    branches = ctor_branches ++ [%{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}]

    args = if has_params?, do: ["msg", "model"], else: ["msg"]

    %{
      name: "update",
      args: args,
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: branches
      }
    }
  end
end
