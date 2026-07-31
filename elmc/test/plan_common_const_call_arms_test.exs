defmodule Elmc.PlanCommonConstCallArmsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}
  alias Elmc.Backend.Plan.CommonConstCallArms

  test "commons switch arms that differ only by a const_int call argument" do
    # Msg tags 1/2 vs helper tags 10/20 — proves remap from arm consts, not peel reuse.
    helper = %{
      name: "apply",
      args: ["tag", "model"],
      type: "Int -> Model -> Model",
      expr: %{op: :var, name: "model"}
    }

    decl = %{
      name: "dispatch",
      args: ["msg", "model"],
      type: "Msg -> Model -> Model",
      expr: %{
        op: :case,
        subject: %{op: :var, name: "msg"},
        branches: [
          %{
            pattern: %{kind: :constructor, name: "Alpha", tag: 1, arg_pattern: nil},
            expr: %{
              op: :qualified_call,
              target: "Main.apply",
              args: [%{op: :int_literal, value: 10, union_ctor: "Main.X"}, %{op: :var, name: "model"}]
            }
          },
          %{
            pattern: %{kind: :constructor, name: "Beta", tag: 2, arg_pattern: nil},
            expr: %{
              op: :qualified_call,
              target: "Main.apply",
              args: [%{op: :int_literal, value: 20, union_ctor: "Main.Y"}, %{op: :var, name: "model"}]
            }
          },
          %{pattern: %{kind: :wildcard}, expr: %{op: :var, name: "model"}}
        ]
      }
    }

    decl_map = %{
      {"Main", "dispatch"} => decl,
      {"Main", "apply"} => helper
    }

    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_constructor_tags, %{"Alpha" => 1, "Beta" => 2, "Main.X" => 10, "Main.Y" => 20})
    Process.put(:elmc_enum_ctors, MapSet.new(["Main.X", "Main.Y", "X", "Y"]))
    Process.put(:elmc_enum_types, MapSet.new(["Main.Dir", "Dir"]))
    Process.put(:elmc_codegen_opts, %{codegen_profile: :size, plan_ir_mode: :primary})

    on_exit(fn ->
      Process.delete(:elmc_program_decls)
      Process.delete(:elmc_constructor_tags)
      Process.delete(:elmc_enum_ctors)
      Process.delete(:elmc_enum_types)
      Process.delete(:elmc_codegen_opts)
      Process.delete(:elmc_union_constructor_macros)
    end)

    assert {:ok, plan} = PlanLower.lower(decl, "Main", decl_map, rc_required: true)

    call_blocks =
      plan.blocks
      |> Enum.count(fn %Block{instrs: instrs} ->
        Enum.any?(instrs, fn
          %{op: :call_fn, args: %{name: "apply"}} -> true
          _ -> false
        end)
      end)

    assert call_blocks == 1, "expected one shared apply call block, got #{call_blocks}"

    stub_consts =
      plan.blocks
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(fn
        %{op: :const_int, args: %{value: v, union_ctor: ctor}}
        when v in [10, 20] and is_binary(ctor) ->
          true

        _ ->
          false
      end)

    assert Enum.any?(stub_consts, &(&1.args.value == 10))
    assert Enum.any?(stub_consts, &(&1.args.value == 20))

    c = CLowerFunction.emit(plan)
    assert c =~ "elmc_fn_Main_apply"
    # Helper tags from arm bodies, not Msg tags 1/2.
    assert c =~ "10" or c =~ "ELMC_UNION"
    refute Regex.match?(~r/elmc_fn_Main_apply\([^)]+\).*elmc_fn_Main_apply\(/s, c)
  end

  test "does not common arms with different callees" do
    blocks = [
      %Block{
        id: 0,
        instrs: [],
        terminator: {:switch_tag, 0, [{1, 1, "A"}, {2, 2, "B"}], 3}
      },
      %Block{
        id: 1,
        instrs: [
          %Types{
            id: 1,
            op: :const_int,
            dest: 10,
            args: %{value: 1, union_ctor: "Main.X"},
            effects: %{fallible: false, borrows: [], consumes: [], produces: nil},
            block_id: 1,
            span: nil
          },
          %Types{
            id: 2,
            op: :call_fn,
            dest: 20,
            args: %{module: "Main", name: "foo", args: [10]},
            effects: %{fallible: true, borrows: [], consumes: [], produces: {:owned, 20}},
            block_id: 1,
            span: nil
          }
        ],
        terminator: {:br, 3}
      },
      %Block{
        id: 2,
        instrs: [
          %Types{
            id: 3,
            op: :const_int,
            dest: 11,
            args: %{value: 2, union_ctor: "Main.Y"},
            effects: %{fallible: false, borrows: [], consumes: [], produces: nil},
            block_id: 2,
            span: nil
          },
          %Types{
            id: 4,
            op: :call_fn,
            dest: 20,
            args: %{module: "Main", name: "bar", args: [11]},
            effects: %{fallible: true, borrows: [], consumes: [], produces: {:owned, 20}},
            block_id: 2,
            span: nil
          }
        ],
        terminator: {:br, 3}
      },
      %Block{id: 3, instrs: [], terminator: {:ret, :fn_out}}
    ]

    plan = %FunctionPlan{
      module: "Main",
      name: "f",
      params: [],
      blocks: blocks,
      entry_block: 0,
      reg_count: 30,
      rc_required: true
    }

    out = CommonConstCallArms.run(plan)
    assert length(out.blocks) == length(plan.blocks)
  end
end
