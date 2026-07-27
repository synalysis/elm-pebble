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
    assert sized[:size_prune_capabilities] == true
    assert SizeProfile.prune_capabilities?(sized)
  end

  test "prune_capabilities enables compact draw for text+clear subsets" do
    alias Elmc.Backend.Pebble.FeatureFlags.DrawFlags.Compact

    flags = %{
      draw_clear: true,
      draw_text: true,
      draw_fill_rect: false,
      draw_rect: false,
      draw_pixel: false,
      draw_line: false,
      draw_circle: false,
      draw_fill_circle: false,
      draw_round_rect: false,
      draw_arc: false,
      draw_path: false,
      draw_fill_radial: false,
      draw_bitmap_in_rect: false,
      draw_vector_at: false,
      draw_vector_sequence_at: false,
      draw_bitmap_sequence_at: false,
      draw_rotated_bitmap: false,
      draw_context: false,
      draw_stroke_width: false,
      draw_antialiased: false,
      draw_stroke_color: false,
      draw_fill_color: false,
      draw_text_color: false,
      draw_compositing_mode: false,
      draw_text_int: false,
      draw_text_label: false,
      draw_text_any: true,
      compact_draw: false
    }

    refute Compact.compute(flags).compact_draw
    assert Compact.compute(flags, %{codegen_profile: :size, size_prune_capabilities: true}).compact_draw
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
