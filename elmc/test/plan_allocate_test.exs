defmodule Elmc.PlanAllocateTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Allocate
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  test "reuses owned slots when register live ranges do not overlap" do
    # reg 0 dies before reg 1 is defined (consumed at idx 1, reg 1 defined at idx 2)
    plan = %FunctionPlan{
      module: "Main",
      name: "probe",
      params: [],
      return_type: nil,
      fallible: true,
      rc_required: true,
      reg_count: 2,
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %{
              op: :const_int,
              dest: 0,
              args: %{value: 1},
              effects: %{produces: {:owned, 0}, consumes: [], borrows: [], fallible: false}
            },
            %{
              op: :release,
              dest: nil,
              args: %{reg: 0},
              effects: %{produces: nil, consumes: [0], borrows: [], fallible: false}
            },
            %{
              op: :const_int,
              dest: 1,
              args: %{value: 2},
              effects: %{produces: {:owned, 1}, consumes: [], borrows: [], fallible: false}
            }
          ],
          terminator: {:ret, 1}
        }
      ],
      entry_block: 0,
      locals: %{},
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil
    }

    {slots, count} = Allocate.run(plan)

    assert Map.get(slots, 0) == 0
    assert Map.get(slots, 1) == 0
    assert count == 1
  end
end
