defmodule Elmc.SizeProfileTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.SizeProfile

  test ":size profile enables size-oriented codegen flags" do
    sized =
      SizeProfile.apply(%{
        codegen_profile: :size,
        direct_render_only: false
      })

    assert sized[:strip_dead_code] == true
    assert sized[:prune_runtime] == true
    assert sized[:plan_ir_mode] == :primary
    assert sized[:enum_tag_peel] == true
    assert sized[:plan_emit] == :state_switch
    assert sized[:fusion_supersede_native] == true
    assert sized[:size_mod_by_fast] == true
  end

  test ":balanced profile keeps IDE-style defaults without size extras" do
    balanced = SizeProfile.apply(%{codegen_profile: :balanced})

    assert balanced[:strip_dead_code] == true
    assert balanced[:plan_ir_mode] == :primary
    refute balanced[:enum_tag_peel] == true
    refute balanced[:plan_emit] == :state_switch
  end

  test "plan state switch thresholds are stable" do
    assert %{min_blocks: 8, max_owned_slots: 12} ==
             SizeProfile.plan_state_switch_thresholds(%{codegen_profile: :size})
  end
end
