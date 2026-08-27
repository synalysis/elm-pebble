defmodule Elmc.PlanVerifyTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, EpilogueRelease, Types, Verify}
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  defp nested_maybe_good_plan do
    b =
      Builder.new("Main", "update", args: ["model", "msg"], rc_required: true, fallible: true)

    b = Builder.catch_begin(b)
    {from, b1} = Builder.emit_load_param(b, 0)
    {to, b2} = Builder.emit_load_param(b1, 1)
    {callee, b3} = Builder.fresh_reg(b2)

    {_, b4} =
      Builder.emit(b3, :call_fn, %{
        dest: callee,
        args: %{module: "Main", name: "lookupVector", args: [from, to]},
        effects: Types.fallible_effects(callee, [], [from, to])
      })

    {_, b5} =
      Builder.emit(b4, :maybe_is_nothing, %{
        args: %{reg: callee},
        effects: %{produces: nil, consumes: [], borrows: [callee], fallible: false}
      })

    b5a = Builder.emit_release(b5, callee)

    {_, b6} =
      Builder.emit(b5a, :publish, %{
        dest: :fn_out,
        args: %{},
        effects: Types.empty_effects()
      })

    b7 = Builder.catch_end(b6)
    b8 = Builder.emit_ret(b7, :fn_out)
    Builder.to_function_plan(b8)
  end

  defp leaked_plan do
    b = Builder.new("Main", "leak", args: [], rc_required: true)
    {reg1, b1} = Builder.emit_const_int(b, 1)
    {_reg2, b2} = Builder.emit_const_int(b1, 2)
    b3 = Builder.emit_ret(b2, reg1)
    Builder.to_function_plan(b3)
  end

  defp double_publish_plan do
    b =
      Builder.new("Main", "bad", args: [], rc_required: true)
      |> Builder.catch_begin()

    {_, b1} =
      Builder.emit(b, :publish, %{dest: :fn_out, args: %{}, effects: Types.empty_effects()})

    {_, b2} =
      Builder.emit(b1, :publish, %{dest: :fn_out, args: %{}, effects: Types.empty_effects()})

    b3 = Builder.catch_end(b2)
    b4 = Builder.emit_ret(b3, :fn_out)
    Builder.to_function_plan(b4)
  end

  test "companion send plan verifies — intermediates in scratch regs, single fn_out publish" do
    plan = Elmc.PlanFixtures.companion_send_plan()
    assert %FunctionPlan{rc_required: true} = plan
    assert :ok = Verify.run(plan)
    refute plan.blocks == []
  end

  test "nested maybe plan verifies — callee in owned reg before maybe inspect" do
    assert :ok = Verify.run(nested_maybe_good_plan())
  end

  test "rejects leaked owned register at function exit" do
    assert {:error, :leaked_owned_regs, _} = Verify.run(leaked_plan())
  end

  test "EpilogueRelease inserts plan release ops so ret blocks verify" do
    plan = leaked_plan() |> EpilogueRelease.run()
    assert :ok = Verify.run(plan)
    [%{instrs: instrs} | _] = plan.blocks
    assert Enum.any?(instrs, &(&1.op == :release))
  end

  test "rejects double fn_out publish" do
    assert {:error, :double_fn_out_publish, _} = Verify.run(double_publish_plan())
  end

  test "phi respects effects.consumes when cond local stays live after merge" do
    b = Builder.new("Main", "init", args: [], rc_required: true, fallible: true)

    {then_reg, b1} = Builder.emit_const_int(b, 1)
    {else_reg, b2} = Builder.emit_const_int(b1, 2)
    {cond_reg, b3} = Builder.emit_const_int(b2, 1)
    {merge_reg, b4} = Builder.fresh_reg(b3)

    {_, b5} =
      Builder.emit(b4, :phi, %{
        dest: merge_reg,
        args: %{then: then_reg, else: else_reg, cond: cond_reg},
        effects: %{
          produces: {:owned, merge_reg},
          consumes: [then_reg, else_reg],
          borrows: [],
          fallible: false
        }
      })

    {retained, b6} =
      Builder.emit(b5, :call_runtime, %{
        dest: merge_reg + 1,
        args: %{builtin: :retain, args: [cond_reg]},
        effects: %{
          produces: {:owned, merge_reg + 1},
          consumes: [],
          borrows: [cond_reg],
          fallible: false
        }
      })

    b7 = Builder.emit_release(b6, merge_reg)
    plan = b7 |> Builder.emit_ret(retained) |> Builder.to_function_plan() |> EpilogueRelease.run()

    assert :ok = Verify.run(plan)
  end

  test "rejects entry block with permanent :none terminator" do
    plan = %FunctionPlan{
      name: "dead_entry",
      module: "Main",
      params: ["msg"],
      rc_required: true,
      reg_count: 2,
      entry_block: 0,
      blocks: [
        %Block{id: 0, instrs: [], terminator: :none},
        %Block{id: 1, instrs: [], terminator: {:ret, :fn_out}}
      ]
    }

    assert {:error, :permanent_none_terminator, [block: 0]} = Verify.run(plan)
  end

  test "rejects dangling branch target" do
    plan = %FunctionPlan{
      name: "dangling",
      module: "Main",
      params: [],
      rc_required: true,
      reg_count: 1,
      entry_block: 0,
      blocks: [
        %Block{id: 0, instrs: [], terminator: {:br, 99}},
        %Block{id: 1, instrs: [], terminator: {:ret, :fn_out}}
      ]
    }

    assert {:error, :dangling_branch_target, [from: 0, target: 99]} = Verify.run(plan)
  end

  test "rejects unreachable arm block" do
    plan = %FunctionPlan{
      name: "orphan_arm",
      module: "Main",
      params: [],
      rc_required: true,
      reg_count: 1,
      entry_block: 0,
      blocks: [
        %Block{id: 0, instrs: [], terminator: {:ret, :fn_out}},
        %Block{id: 1, instrs: [], terminator: {:ret, :fn_out}}
      ]
    }

    assert {:error, :unreachable_block, [block: 1, entry: 0]} = Verify.run(plan)
  end

  test "rejects fusion_c-only plans" do
    plan = %FunctionPlan{
      name: "fused",
      module: "Main",
      params: [],
      rc_required: true,
      blocks: [],
      entry_block: 0,
      fusion_c: "RC Rc = RC_SUCCESS;\nreturn Rc;"
    }

    assert {:error, :unverified_fusion_c, _} = Verify.run(plan)
  end

  test "rejects leaked owned that flows across br to ret" do
    produce =
      %Types{
        id: 0,
        op: :const_int,
        dest: 0,
        args: %{value: 1},
        effects: Types.owned_effects(0),
        block_id: 0,
        span: nil
      }

    plan = %FunctionPlan{
      name: "cross_block_leak",
      module: "Main",
      params: [],
      rc_required: true,
      reg_count: 1,
      entry_block: 0,
      blocks: [
        %Block{id: 0, instrs: [produce], terminator: {:br, 1}},
        %Block{id: 1, instrs: [], terminator: {:ret, :fn_out}}
      ]
    }

    assert {:error, :leaked_owned_regs, meta} = Verify.run(plan)
    assert 0 in meta[:regs]
  end

  test "rejects read-after-consume across blocks" do
    produce =
      %Types{
        id: 0,
        op: :const_int,
        dest: 0,
        args: %{value: 1},
        effects: Types.owned_effects(0),
        block_id: 0,
        span: nil
      }

    release =
      %Types{
        id: 1,
        op: :release,
        dest: nil,
        args: %{reg: 0},
        effects: %{produces: nil, consumes: [0], borrows: [], fallible: false},
        block_id: 0,
        span: nil
      }

    borrow =
      %Types{
        id: 2,
        op: :maybe_is_nothing,
        dest: nil,
        args: %{reg: 0},
        effects: %{produces: nil, consumes: [], borrows: [0], fallible: false},
        block_id: 1,
        span: nil
      }

    plan = %FunctionPlan{
      name: "uaf",
      module: "Main",
      params: [],
      rc_required: true,
      reg_count: 1,
      entry_block: 0,
      blocks: [
        %Block{id: 0, instrs: [produce, release], terminator: {:br, 1}},
        %Block{id: 1, instrs: [borrow], terminator: {:ret, :fn_out}}
      ]
    }

    assert {:error, :read_after_consume, _} = Verify.run(plan)
  end

  test "phi merge intersects must-own and still catches a one-arm leak" do
    then_prod =
      %Types{
        id: 0,
        op: :const_int,
        dest: 1,
        args: %{value: 1},
        effects: Types.owned_effects(1),
        block_id: 1,
        span: nil
      }

    else_prod =
      %Types{
        id: 1,
        op: :const_int,
        dest: 2,
        args: %{value: 2},
        effects: Types.owned_effects(2),
        block_id: 2,
        span: nil
      }

    leak_prod =
      %Types{
        id: 2,
        op: :const_int,
        dest: 4,
        args: %{value: 9},
        effects: Types.owned_effects(4),
        block_id: 2,
        span: nil
      }

    phi =
      %Types{
        id: 3,
        op: :phi,
        dest: 3,
        args: %{then: 1, else: 2, cond: 0},
        effects: %{
          produces: {:owned, 3},
          consumes: [1, 2],
          borrows: [],
          fallible: false
        },
        block_id: 3,
        span: nil
      }

    balanced = %FunctionPlan{
      name: "phi_ok",
      module: "Main",
      params: [],
      rc_required: true,
      reg_count: 4,
      entry_block: 0,
      blocks: [
        %Block{id: 0, instrs: [], terminator: {:br_if, 1, 2, 0}},
        %Block{id: 1, instrs: [then_prod], terminator: {:br, 3}},
        %Block{id: 2, instrs: [else_prod], terminator: {:br, 3}},
        %Block{id: 3, instrs: [phi], terminator: {:ret, 3}}
      ]
    }

    assert :ok = Verify.run(balanced)

    leaked = %FunctionPlan{
      balanced
      | name: "phi_one_arm_leak",
        reg_count: 5,
        blocks: [
          %Block{id: 0, instrs: [], terminator: {:br_if, 1, 2, 0}},
          %Block{id: 1, instrs: [then_prod], terminator: {:br, 3}},
          %Block{id: 2, instrs: [else_prod, leak_prod], terminator: {:br, 3}},
          %Block{id: 3, instrs: [phi], terminator: {:ret, 3}}
        ]
    }

    assert {:error, :leaked_owned_regs, meta} = Verify.run(leaked)
    assert 4 in meta[:regs]

    released = EpilogueRelease.run(leaked)
    merge_block = Enum.find(released.blocks, &(&1.id == 3))
    assert Enum.any?(merge_block.instrs, &(&1.op == :release and &1.args.reg == 4))
    assert :ok = Verify.run(released)
  end

  test "EpilogueRelease frees a pre-split owned reg on the arm that does not consume it" do
    kind =
      %Types{
        id: 0,
        op: :const_int,
        dest: 1,
        args: %{value: 1},
        effects: Types.owned_effects(1),
        block_id: 0,
        span: nil
      }

    consume =
      %Types{
        id: 1,
        op: :call_fn,
        dest: 2,
        args: %{args: [1]},
        effects: %{
          produces: {:owned, 2},
          consumes: [1],
          borrows: [],
          fallible: false
        },
        block_id: 2,
        span: nil
      }

    plan = %FunctionPlan{
      name: "one_arm_consume",
      module: "Main",
      params: [],
      rc_required: true,
      reg_count: 3,
      entry_block: 0,
      blocks: [
        %Block{id: 0, instrs: [kind], terminator: {:br_if, 1, 2, 0}},
        %Block{id: 1, instrs: [], terminator: {:br, 3}},
        %Block{id: 2, instrs: [consume], terminator: {:br, 3}},
        %Block{id: 3, instrs: [], terminator: {:ret, :stream_void}}
      ]
    }

    assert {:error, :leaked_owned_regs, meta} = Verify.run(plan)
    assert 1 in meta[:regs]

    released = EpilogueRelease.run(plan)
    then_block = Enum.find(released.blocks, &(&1.id == 1))
    else_block = Enum.find(released.blocks, &(&1.id == 2))

    assert Enum.any?(then_block.instrs, &(&1.op == :release and &1.args.reg == 1))
    refute Enum.any?(else_block.instrs, &(&1.op == :release and &1.args.reg == 1))
    assert :ok = Verify.run(released)
  end

  test "rejects borrow of a register owned on only one incoming edge" do
    then_prod =
      %Types{
        id: 0,
        op: :const_int,
        dest: 1,
        args: %{value: 1},
        effects: Types.owned_effects(1),
        block_id: 1,
        span: nil
      }

    borrow =
      %Types{
        id: 1,
        op: :maybe_is_nothing,
        dest: nil,
        args: %{reg: 1},
        effects: %{produces: nil, consumes: [], borrows: [1], fallible: false},
        block_id: 3,
        span: nil
      }

    plan = %FunctionPlan{
      name: "asymmetric_borrow",
      module: "Main",
      params: [],
      rc_required: true,
      reg_count: 2,
      entry_block: 0,
      blocks: [
        %Block{id: 0, instrs: [], terminator: {:br_if, 1, 2, 0}},
        %Block{id: 1, instrs: [then_prod], terminator: {:br, 3}},
        %Block{id: 2, instrs: [], terminator: {:br, 3}},
        %Block{id: 3, instrs: [borrow], terminator: {:ret, :fn_out}}
      ]
    }

    assert {:error, :asymmetric_owned_borrow, _} = Verify.run(plan)
  end

  test "rejects mid-branch fn_out write then later produce" do
    pub =
      %Types{
        id: 0,
        op: :publish,
        dest: :fn_out,
        args: %{},
        effects: Types.empty_effects(),
        block_id: 0,
        span: nil
      }

    later =
      %Types{
        id: 1,
        op: :const_int,
        dest: 1,
        args: %{value: 2},
        effects: Types.owned_effects(1),
        block_id: 0,
        span: nil
      }

    plan = %FunctionPlan{
      name: "mid_out",
      module: "Main",
      params: [],
      rc_required: true,
      reg_count: 2,
      entry_block: 0,
      blocks: [
        %Block{id: 0, instrs: [pub, later], terminator: {:ret, :fn_out}}
      ]
    }

    assert {:error, :mid_branch_fn_out, _} = Verify.run(plan)
  end
end
