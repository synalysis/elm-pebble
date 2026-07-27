defmodule Elmc.PlanParamCfgArmTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Builder

  test "get_or_load_param reloads closure params in each cfg arm block" do
    b0 = Builder.new("Pages.Internal.ResponseSketch", "closure", args: ["action"], rc_required: true)

    arm1_id = b0.next_block
    b1 = Builder.begin_cfg_arm_block(b0, arm1_id)
    {reg1, b1_loaded} = Builder.get_or_load_param(b1, 0, "action")
    b1_done = Builder.finish_block(b1_loaded, :none)

    arm2_id = b1_done.next_block
    b2 = Builder.begin_cfg_arm_block(b1_done, arm2_id)
    {reg2, b2_loaded} = Builder.get_or_load_param(b2, 0, "action")
    b2_done = Builder.finish_block(b2_loaded, :none)

    load_param_instrs =
      (b2_done.blocks ++ [b2_done.current_block])
      |> Enum.flat_map(& &1.instrs)
      |> Enum.filter(&(&1.op == :load_param))

    assert length(load_param_instrs) == 2
    assert reg1 != reg2
    assert Enum.all?(load_param_instrs, &(&1.args.index == 0))
  end
end
