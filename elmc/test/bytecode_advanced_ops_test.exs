defmodule Elmc.BytecodeAdvancedOpsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Bytecode.Runtime
  alias Elmc.Backend.Plan.Builder
  alias Elmc.Backend.Plan.Lower.Function, as: PlanLower
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan, Param}

  @moduletag :plan_surface

  test "call_closure invokes a make_closure value" do
    identity_lambda = identity_lambda_plan("Main", "id_lam")

    {parent, _} =
      Builder.new("Main", "callId", args: ["x"])
      |> then(fn b ->
        {x_reg, b1} = Builder.get_or_load_param(b, 0, "x")
        {closure_reg, b2} = Builder.fresh_reg(b1)

        {_, b3} =
          Builder.emit(b2, :make_closure, %{
            dest: closure_reg,
            args: %{index: 0, arity: 1, captures: []},
            effects: Types.fallible_effects(closure_reg)
          })

        {dest, b4} = Builder.fresh_reg(b3)

        {_, b5} =
          Builder.emit(b4, :call_closure, %{
            dest: dest,
            args: %{callee: closure_reg, args: [x_reg]},
            effects: Types.fallible_effects(dest, [x_reg], [closure_reg])
          })

        {Builder.to_function_plan(Builder.emit_ret(b5, dest)), b5}
      end)

    parent = %{parent | lambdas: [identity_lambda], lambda_arg_count: 1}

    assert {:ok, 9} = Runtime.run_function(parent, params: [9])
  end

  test "list_cursor_map runs List.range-style loop lambda" do
    zero_lambda = zero_lambda_plan("Main", "zero_lam")

    {parent, _} =
      Builder.new("Main", "rows", args: [])
      |> then(fn b ->
        {dest, b1} = Builder.fresh_reg(b)

        {_, b2} =
          Builder.emit(b1, :list_cursor_map, %{
            dest: dest,
            args: %{
              start: 0,
              end: 2,
              lambda_idx: 0,
              start_literal?: true,
              end_literal?: true
            },
            effects: Types.fallible_effects(dest)
          })

        {Builder.to_function_plan(Builder.emit_ret(b2, dest)), b2}
      end)

    parent = %{parent | lambdas: [zero_lambda]}

    assert {:ok, [0, 0, 0]} = Runtime.run_function(parent, params: [])
  end

  test "forward_ref ops store and reload closure values" do
    ref = "elmc_plan_letrec_g_0"
    identity_lambda = identity_lambda_plan("Main", "g_lam")

    {parent, _} =
      Builder.new("Main", "loadG", args: [])
      |> then(fn b ->
        {closure_reg, b1} = Builder.fresh_reg(b)

        {_, b2} =
          Builder.emit(b1, :make_closure, %{
            dest: closure_reg,
            args: %{index: 0, arity: 1, captures: []},
            effects: Types.fallible_effects(closure_reg)
          })

        {_, b3} =
          Builder.emit(b2, :forward_ref_set, %{
            dest: nil,
            args: %{ref: ref, value: closure_reg},
            effects: Types.empty_effects()
          })

        {loaded_reg, b4} = Builder.fresh_reg(b3)

        {_, b5} =
          Builder.emit(b4, :forward_ref_load, %{
            dest: loaded_reg,
            args: %{ref: ref},
            effects: Types.owned_effects(loaded_reg)
          })

        {arg_reg, b6} = Builder.fresh_reg(b5)

        {_, b7} =
          Builder.emit(b6, :const_int, %{
            dest: arg_reg,
            args: %{value: 7},
            effects: Types.empty_effects()
          })

        {dest, b8} = Builder.fresh_reg(b7)

        {_, b9} =
          Builder.emit(b8, :call_closure, %{
            dest: dest,
            args: %{callee: loaded_reg, args: [arg_reg]},
            effects: Types.fallible_effects(dest, [arg_reg], [loaded_reg])
          })

        {Builder.to_function_plan(Builder.emit_ret(b9, dest)), b9}
      end)

    parent = %{parent | lambdas: [identity_lambda], lambda_arg_count: 1, letrec_refs: [ref]}

    assert {:ok, 7} = Runtime.run_function(parent, params: [])
  end

  test "plan lowering emits advanced ops for list range map and letrec" do
    rows_decl = %{
      name: "rows",
      args: [],
      expr: %{
        op: :qualified_call,
        target: "List.map",
        args: [
          %{op: :lambda, args: ["i"], body: %{op: :int_literal, value: 0}},
          %{
            op: :qualified_call,
            target: "List.range",
            args: [%{op: :int_literal, value: 0}, %{op: :int_literal, value: 2}]
          }
        ]
      }
    }

    assert {:ok, plan} = PlanLower.lower(rows_decl, "Grid", %{}, rc_required: true)
    ops = plan_ops(plan)
    assert :list_cursor_map in ops

    letrec_decl = %{
      name: "loop",
      args: [],
      expr: %{
        op: :let_in,
        name: "f",
        value_expr: %{
          op: :lambda,
          args: ["x"],
          body: %{
            op: :call,
            name: "f",
            args: [%{op: :var, name: "x"}]
          }
        },
        in_expr: %{
          op: :call,
          name: "f",
          args: [%{op: :int_literal, value: 1}]
        }
      }
    }

    assert {:ok, letrec_plan} = PlanLower.lower(letrec_decl, "Main", %{}, rc_required: true)
    letrec_ops = plan_ops(letrec_plan)
    assert :forward_ref_set in letrec_ops
    assert :forward_ref_capture in letrec_ops or :forward_ref_load in letrec_ops
  end

  defp identity_lambda_plan(module, name) do
    %FunctionPlan{
      module: module,
      name: name,
      params: [%Param{name: "x", type: "Int", index: 0}],
      return_type: "Int",
      fallible: true,
      rc_required: true,
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %Types{
              id: 1,
              op: :load_param,
              dest: 0,
              args: %{index: 0},
              effects: Types.empty_effects(),
              block_id: 0,
              span: nil
            },
            %Types{
              id: 2,
              op: :publish,
              dest: :fn_out,
              args: %{source: 0},
              effects: Types.empty_effects(),
              block_id: 0,
              span: nil
            }
          ],
          terminator: {:ret, :fn_out}
        }
      ],
      entry_block: 0,
      locals: %{},
      reg_count: 1,
      catch_depth: 1,
      lambdas: [],
      lambda_arg_count: 1,
      letrec_refs: []
    }
  end

  defp zero_lambda_plan(module, name) do
    %FunctionPlan{
      module: module,
      name: name,
      params: [%Param{name: "i", type: "Int", index: 0}],
      return_type: "Int",
      fallible: true,
      rc_required: true,
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %Types{
              id: 1,
              op: :const_int,
              dest: 0,
              args: %{value: 0},
              effects: Types.empty_effects(),
              block_id: 0,
              span: nil
            },
            %Types{
              id: 2,
              op: :publish,
              dest: :fn_out,
              args: %{source: 0},
              effects: Types.empty_effects(),
              block_id: 0,
              span: nil
            }
          ],
          terminator: {:ret, :fn_out}
        }
      ],
      entry_block: 0,
      locals: %{},
      reg_count: 1,
      catch_depth: 1,
      lambdas: [],
      lambda_arg_count: 1,
      letrec_refs: []
    }
  end

  defp plan_ops(%FunctionPlan{blocks: blocks}) do
    blocks
    |> Enum.flat_map(& &1.instrs)
    |> Enum.map(& &1.op)
    |> MapSet.new()
  end
end
