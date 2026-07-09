defmodule Elmc.PlanMakeClosureCTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.Lower.Function, as: CLowerFunction
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan, Param}

  @moduletag :plan_surface

  test "plan make_closure lowers to closure helper and elmc_closure_new_rc" do
    lambda_plan = %FunctionPlan{
      module: "Main",
      name: "makeF$λ0",
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
      lambda_arg_count: 1
    }

    parent = %FunctionPlan{
      module: "Main",
      name: "makeF",
      params: [],
      return_type: "Int",
      fallible: true,
      rc_required: true,
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %Types{
              id: 10,
              op: :make_closure,
              dest: 0,
              args: %{index: 0, arity: 1, captures: []},
              effects: Types.fallible_effects(0),
              block_id: 0,
              span: nil
            }
          ],
          terminator: {:ret, 0}
        }
      ],
      entry_block: 0,
      locals: %{},
      reg_count: 1,
      catch_depth: 1,
      lambdas: [lambda_plan],
      lambda_arg_count: nil
    }

    Process.put(:elmc_lambdas, [])
    Process.put(:elmc_plan_closure_emitted, MapSet.new())
    on_exit(fn ->
      Process.delete(:elmc_lambdas)
      Process.delete(:elmc_plan_closure_emitted)
    end)

    body = CLowerFunction.emit(parent)

    assert body =~ "elmc_closure_new_rc(&owned[0], elmc_fn_Main_makeF_closure_0"
    refute body =~ "plan make_closure"

    [closure_def | _] = Process.get(:elmc_lambdas, [])
    assert closure_def =~ "static RC elmc_fn_Main_makeF_closure_0"
    assert closure_def =~ "args[0]"
  end

  test "closure emit uses captures and args not bare Elm param names" do
    lambda_plan = %FunctionPlan{
      module: "Main",
      name: "view$λ0",
      params: [
        %Param{name: "layout", type: "Layout", index: 0},
        %Param{name: "index", type: "Int", index: 1},
        %Param{name: "value", type: "Int", index: 2}
      ],
      return_type: "UiNode",
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
              op: :load_param,
              dest: 1,
              args: %{index: 1},
              effects: Types.empty_effects(),
              block_id: 0,
              span: nil
            },
            %Types{
              id: 3,
              op: :load_param,
              dest: 2,
              args: %{index: 2},
              effects: Types.empty_effects(),
              block_id: 0,
              span: nil
            },
            %Types{
              id: 4,
              op: :call,
              dest: :fn_out,
              args: %{
                target: {"Main", "drawCell"},
                args: [0, 1, 2]
              },
              effects: Types.fallible_effects(nil),
              block_id: 0,
              span: nil
            }
          ],
          terminator: {:ret, :fn_out}
        }
      ],
      entry_block: 0,
      locals: %{},
      reg_count: 3,
      catch_depth: 1,
      lambdas: [],
      lambda_arg_count: 2
    }

    parent = %FunctionPlan{
      module: "Main",
      name: "view",
      params: [%Param{name: "model", type: "Model", index: 0}],
      return_type: "UiNode",
      fallible: true,
      rc_required: true,
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %Types{
              id: 10,
              op: :make_closure,
              dest: 0,
              args: %{index: 0, arity: 2, captures: [0]},
              effects: Types.fallible_effects(0),
              block_id: 0,
              span: nil
            }
          ],
          terminator: {:ret, 0}
        }
      ],
      entry_block: 0,
      locals: %{},
      reg_count: 1,
      catch_depth: 1,
      lambdas: [lambda_plan],
      lambda_arg_count: nil
    }

    decl_map = %{
      {"Main", "view"} => %{name: "view", ownership: [:borrow_arg, :borrow_result]},
      {"Main", "drawCell"} => %{name: "drawCell", ownership: [:borrow_arg, :borrow_result]}
    }

    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_lambdas, [])
    Process.put(:elmc_plan_closure_emitted, MapSet.new())

    on_exit(fn ->
      Process.delete(:elmc_program_decls)
      Process.delete(:elmc_lambdas)
      Process.delete(:elmc_plan_closure_emitted)
    end)

    _body = CLowerFunction.emit(parent)

    [closure_def | _] = Process.get(:elmc_lambdas, [])
    assert closure_def =~ "captures[0]"
    assert closure_def =~ "args[0]"
    refute closure_def =~ ~r/\blayout\b/
    refute closure_def =~ ~r/\bindex\b/
  end
end
