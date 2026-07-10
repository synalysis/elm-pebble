defmodule Elmc.RecordGetHoistPassTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.DirectRender.Emit.RecordGetHoistPass

  test "hoists repeated ELMC_RECORD_GET_INDEX_INT on the same record field" do
    code = """
    scene_cmd.p0 = ELMC_RECORD_GET_INDEX_INT(layout, 2 /* cx */);
    scene_cmd.p1 = ELMC_RECORD_GET_INDEX_INT(layout, 3 /* cy */);
    scene_cmd.p2 = ELMC_RECORD_GET_INDEX_INT(layout, 2 /* cx */);
    scene_cmd.p3 = ELMC_RECORD_GET_INDEX_INT(layout, 2 /* cx */);
    """

    out = RecordGetHoistPass.run(code)

    assert out =~ "const elmc_int_t direct_hoisted_rec_1 = ELMC_RECORD_GET_INDEX_INT(layout, 2 /* cx */);"
    assert :binary.matches(out, "direct_hoisted_rec_1") |> length() == 4
    refute out =~ "scene_cmd.p0 = ELMC_RECORD_GET_INDEX_INT(layout, 2 /* cx */);"
    assert out =~ "ELMC_RECORD_GET_INDEX_INT(layout, 3 /* cy */);"
  end

  test "leaves single-use record getters unchanged" do
    code = "scene_cmd.p0 = ELMC_RECORD_GET_INDEX_INT(layout, 2 /* cx */);"
    assert RecordGetHoistPass.run(code) == code
  end
end
