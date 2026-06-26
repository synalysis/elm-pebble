defmodule Elmc.Backend.Pebble.DrawKindLutsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Pebble.Kinds.Tables.DrawKindLuts
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.DrawSettings.KindSwitch
  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds.IsVisual
  alias Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds.RequiresFullDirty

  test "visual predicate lut covers dense draw kinds" do
    code = IsVisual.body()

    assert code =~ "static const uint8_t elmc_pebble_draw_kind_visual_lut[33]"
    assert code =~ "[2] = 1"
    refute code =~ "switch (cmd->kind)"
    assert code =~ "elmc_pebble_draw_kind_visual_lut[(cmd->kind)]"
  end

  test "full dirty predicate lut replaces switch" do
    code = RequiresFullDirty.body()

    assert code =~ "static const uint8_t elmc_pebble_draw_kind_full_dirty_lut[33]"
    assert code =~ "[12] = 1"
    refute code =~ "switch (cmd->kind)"
    assert code =~ "elmc_pebble_draw_kind_full_dirty_lut[(cmd->kind)]"
  end

  test "draw setting tag lut replaces switch" do
    code = KindSwitch.body()

    assert code =~ "static const int16_t elmc_pebble_draw_setting_kind_lut[7]"
    assert code =~ "ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH"
    assert code =~ "elmc_pebble_draw_setting_kind_lut[setting_tag]"
    refute code =~ "switch (setting_tag)"
  end

  test "path kinds are feature guarded in visual lut" do
    lut =
      DrawKindLuts.predicate_lut_c("elmc_pebble_draw_kind_visual_lut", DrawKindLuts.visual_kinds())

    assert lut =~ "#if ELMC_PEBBLE_FEATURE_DRAW_PATH"
    assert lut =~ "[20] = 1"
  end
end
