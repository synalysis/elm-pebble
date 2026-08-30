defmodule Elmc.WasmCfgLowerTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.Plan.Lower.Function, as: PlanFn
  alias Elmc.Backend.Wasm.Lower.Function, as: WasmFn

  test "if/merge plan lowers to valid wasm state-switch CFG" do
    decl = %{
      name: "pick",
      args: ["flag"],
      expr: %{
        op: :if,
        cond: %{op: :var, name: "flag"},
        then_expr: %{op: :int_literal, value: 1},
        else_expr: %{op: :int_literal, value: 2}
      }
    }

    assert {:ok, plan} = PlanFn.lower(decl, "Main", %{}, rc_required: true)

    body = WasmFn.lower(plan).body

    assert body =~ "(local $plan_state i32)"
    assert body =~ "$plan_loop"
    assert body =~ "$plan_switch_done"
    assert body =~ "(i32.const 1)"
    assert body =~ "(i32.const 2)"
    refute body =~ "(block $block_3)"

    # if/else arms finish with :none and must fall through to the merge block,
    # not exit the state switch early.
    assert body =~ "(local.set $plan_state (i32.const 3))"
    assert length(Regex.scan(~r/local\.set \$plan_state \(i32\.const -1\)/, body)) == 1
  end

  test "CFG ret nulls owned after moving boxed result into fn_out" do
    decl = %{
      name: "pickString",
      args: ["flag"],
      expr: %{
        op: :if,
        cond: %{op: :var, name: "flag"},
        then_expr: %{op: :string_literal, value: "a"},
        else_expr: %{op: :string_literal, value: "b"}
      }
    }

    assert {:ok, plan} = PlanFn.lower(decl, "Main", %{}, rc_required: true)
    assert length(plan.blocks) > 1

    body = WasmFn.lower(plan).body

    assert body =~ "$plan_loop"
    assert body =~ ~r/local\.set \$fn_out \(local\.get \$reg\d+\)/
    assert body =~ ~r/local\.set \$owned\d+ \(i32\.const 0\)/
    assert body =~ ~r/\(drop\s+\(call \$runtime_release \(local\.get \$owned/
  end

  test "CFG case merge does not mid-body release the published result" do
    Process.put(:elmc_constructor_tags, %{"Maybe.Nothing" => 0, "Maybe.Just" => 1})
    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    decl = %{
      name: "fromMaybe",
      args: ["m"],
      expr: %{
        op: :case,
        subject: %{op: :var, name: "m"},
        branches: [
          %{
            pattern: %{kind: :qualified_constructor, name: "Maybe.Nothing"},
            expr: %{op: :int_literal, value: -1}
          },
          %{
            pattern: %{kind: :var, name: "x"},
            expr: %{op: :var, name: "x"}
          }
        ]
      }
    }

    assert {:ok, plan} = PlanFn.lower(decl, "Main", %{{"Main", "fromMaybe"} => decl}, rc_required: true)
    body = WasmFn.lower(plan).body

    # Plan `:release` is epilogue bookkeeping. Do not `runtime_release` the
    # register published to `$fn_out` (List.tail |> length was a UAF).
    for [reg] <- Regex.scan(~r/local\.set \$fn_out \(local\.get \$(reg\d+)\)/, body, capture: :all_but_first) do
      refute body =~ ~r/call \$runtime_release \(local\.get \$#{Regex.escape(reg)}\)/,
             "must not release $#{reg} after publishing it to $fn_out"
    end

    assert body =~ "runtime_release"
  end

  test "self-tail call on list helper restarts plan_loop instead of recursing" do
    alias Elmc.Backend.Plan.Types
    alias Elmc.Backend.Plan.Types.{Block, FunctionPlan, Param}

    # List-recursion CFG: tail comes from list_tail, then self-call + join.
    plan = %FunctionPlan{
      module: "Main",
      name: "sumHelp",
      params: [
        %Param{name: "acc", type: nil, index: 0},
        %Param{name: "xs", type: nil, index: 1}
      ],
      return_type: nil,
      fallible: true,
      rc_required: true,
      entry_block: 0,
      locals: %{"acc" => 0, "xs" => 1},
      reg_count: 4,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: nil,
      fusion_data: nil,
      native_scalar_return: nil,
      native_scalar_value_return: false,
      fusion_emit: nil,
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %Types{
              op: :call_runtime,
              dest: 2,
              args: %{builtin: :list_tail, args: [1]},
              effects: Types.owned_effects(2)
            },
            %Types{
              op: :call_fn,
              dest: 3,
              args: %{module: "Main", name: "sumHelp", args: [0, 2]},
              effects: Types.owned_effects(3)
            }
          ],
          terminator: {:br, 1}
        },
        %Block{
          id: 1,
          instrs: [
            %Types{
              op: :phi,
              dest: 3,
              args: %{then: 3, else: 3, cond: 0},
              effects: Types.empty_effects()
            }
          ],
          terminator: {:ret, :fn_out}
        }
      ]
    }

    body = WasmFn.lower(plan).body

    assert body =~ "$plan_loop"
    refute body =~ "call $elmc_fn_Main_sumHelp"
    assert body =~ ~r/local\.set \$param0 \(local\.get \$reg0\)/
    assert body =~ ~r/local\.set \$param1 \(local\.get \$reg2\)/
    assert body =~ "(local.set $plan_state (i32.const 0))"
    # TCO LIFO-releases leftover owned slots; skips pointers equal to new params
    # (list_cons'd heads already transfer-nulled in the cons consume).
    assert body =~ "runtime_release"
    refute body =~ "runtime_release_unless_reachable_from_roots"
  end

  test "self-call without list_tail arg is not rewritten as TCO" do
    alias Elmc.Backend.Plan.Types
    alias Elmc.Backend.Plan.Types.{Block, FunctionPlan, Param}

    plan = %FunctionPlan{
      module: "Main",
      name: "update",
      params: [
        %Param{name: "msg", type: nil, index: 0},
        %Param{name: "model", type: nil, index: 1}
      ],
      return_type: nil,
      fallible: true,
      rc_required: true,
      entry_block: 0,
      locals: %{"msg" => 0, "model" => 1},
      reg_count: 3,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: nil,
      fusion_data: nil,
      native_scalar_return: nil,
      native_scalar_value_return: false,
      fusion_emit: nil,
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %Types{
              op: :call_fn,
              dest: 2,
              args: %{module: "Main", name: "update", args: [0, 1]},
              effects: Types.owned_effects(2)
            }
          ],
          terminator: {:br, 1}
        },
        %Block{
          id: 1,
          instrs: [],
          terminator: {:ret, :fn_out}
        }
      ]
    }

    body = WasmFn.lower(plan).body
    assert body =~ "call $elmc_fn_Main_update"
  end

  test "cross-block list peel with catch-wrapped self-call is TCO'd" do
    alias Elmc.Backend.Plan.Types
    alias Elmc.Backend.Plan.Types.{Block, FunctionPlan, Param}

    # Mimic BoundingBox3d.aggregateOfHelp: peel in one block (list_tail +
    # retain/view_peel maybe_just_payload), fallible catch-wrapped self-tail
    # in another.
    plan = %FunctionPlan{
      module: "Main",
      name: "aggHelp",
      params: [
        %Param{name: "acc", type: nil, index: 0},
        %Param{name: "xs", type: nil, index: 1}
      ],
      return_type: nil,
      fallible: true,
      rc_required: true,
      entry_block: 0,
      locals: %{"acc" => 0, "xs" => 1},
      reg_count: 6,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: nil,
      fusion_data: nil,
      native_scalar_return: nil,
      native_scalar_value_return: false,
      fusion_emit: nil,
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %Types{
              op: :call_runtime,
              dest: 2,
              args: %{builtin: :list_tail, args: [1]},
              effects: Types.owned_effects(2)
            },
            %Types{
              op: :call_runtime,
              dest: 3,
              args: %{
                builtin: :retain,
                args: [2],
                view_peel: :maybe_just_payload,
                view_peel_args: [2]
              },
              effects: Types.owned_effects(3)
            }
          ],
          terminator: {:br, 1}
        },
        %Block{
          id: 1,
          instrs: [
            %Types{op: :catch_begin, dest: nil, args: %{}, effects: Types.empty_effects()},
            %Types{
              op: :call_fn,
              dest: 4,
              args: %{module: "Main", name: "aggHelp", args: [0, 3]},
              effects: Types.owned_effects(4)
            },
            %Types{op: :catch_end, dest: nil, args: %{}, effects: Types.empty_effects()}
          ],
          terminator: {:br, 2}
        },
        %Block{
          id: 2,
          instrs: [],
          terminator: {:ret, :fn_out}
        }
      ]
    }

    body = WasmFn.lower(plan).body

    refute body =~ "call $elmc_fn_Main_aggHelp"
    assert body =~ ~r/local\.set \$param0 \(local\.get \$reg0\)/
    assert body =~ ~r/local\.set \$param1 \(local\.get \$reg3\)/
    assert body =~ "(local.set $plan_state (i32.const 0))"
  end
  test "zero-arity top-level value memoizes via value_cache" do
    alias Elmc.Backend.Plan.Types
    alias Elmc.Backend.Plan.Types.{Block, FunctionPlan, Param}

    plan = %FunctionPlan{
      module: "Main",
      name: "expensiveConst",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      entry_block: 0,
      locals: %{},
      reg_count: 1,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: nil,
      fusion_data: nil,
      native_scalar_return: nil,
      native_scalar_value_return: false,
      fusion_emit: nil,
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %Types{
              op: :const_int,
              dest: 0,
              args: %{value: 42},
              effects: Types.empty_effects()
            }
          ],
          terminator: {:ret, 0}
        }
      ]
    }

    body = WasmFn.lower(plan).body
    assert body =~ "value_cache_get"
    assert body =~ "value_cache_put"
  end

end
