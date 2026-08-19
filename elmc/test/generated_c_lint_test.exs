defmodule Elmc.GeneratedCLintTest do
  use ExUnit.Case, async: true

  alias Elmc.TestSupport.GeneratedCLint

  test "flags Elm bind names used as ELMC_RECORD_GET_INDEX bases" do
    source = """
    static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
      ElmcValue *model = (argc > 0) ? args[0] : NULL;
      scene_cmd.p2 = ELMC_RECORD_GET_INDEX_INT(ELMC_RECORD_GET_INDEX(hands, 0), 1);
    }
    """

    assert_raise ExUnit.AssertionError, ~r/undeclared record base.*hands/, fn ->
      GeneratedCLint.assert_record_get_bases_bound!(source)
    end
  end

  test "accepts peeled Just payload and declared params" do
    source = """
    static RC elmc_fn_Main_view_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {
      ElmcValue *model = (argc > 0) ? args[0] : NULL;
      ElmcValue *owned[2] = {0};
      scene_cmd.p2 = ELMC_RECORD_GET_INDEX_INT(ELMC_RECORD_GET_INDEX(elmc_maybe_or_tuple_just_payload_borrow(owned[1]), 0), 1);
      scene_cmd.p0 = ELMC_RECORD_GET_INDEX_INT(model, 0);
    }
    """

    assert :ok = GeneratedCLint.assert_record_get_bases_bound!(source)
  end

  test "bare_record_get_bases extracts only the first GET_INDEX argument" do
    c =
      "ELMC_RECORD_GET_INDEX_INT(ELMC_RECORD_GET_INDEX(hands, ELMC_FIELD_X), ELMC_FIELD_Y)"

    assert GeneratedCLint.bare_record_get_bases(c) == ["hands"]
  end
end
