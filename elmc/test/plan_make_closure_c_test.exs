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
end
