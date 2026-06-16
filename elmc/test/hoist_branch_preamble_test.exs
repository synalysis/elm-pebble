defmodule Elmc.HoistBranchPreambleTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.Hoist

  test "drop_branch_only_redeclared_hoists keeps shared hoists used in else" do
    preamble = """
      const elmc_int_t direct_hoisted_int_32 = 1;
      const elmc_int_t native_min_left_21 = 2;
    """

    then_code = """
      const elmc_int_t native_min_left_21 = 3;
      const elmc_int_t direct_hoisted_int_32 = 4;
    """

    else_code = """
      const elmc_int_t x = direct_hoisted_int_32 + 1;
    """

    result = Hoist.drop_branch_only_redeclared_hoists(preamble, then_code, else_code)

    assert result =~ "direct_hoisted_int_32"
    refute result =~ "native_min_left_21"
  end

  test "drop_branch_only_redeclared_hoists returns empty when all preamble hoists are branch-local" do
    preamble = "  const elmc_int_t native_min_right_21 = 5;\n"

    then_code = """
      const elmc_int_t native_min_right_21 = 6;
      const elmc_int_t y = native_min_right_21;
    """

    else_code = "const elmc_int_t z = 0;\n"

    assert Hoist.drop_branch_only_redeclared_hoists(preamble, then_code, else_code) == ""
  end

  test "drop_unused_native_minmax_decls removes orphaned min results and operands" do
    code = """
      const elmc_int_t native_min_6 = 144;
      const elmc_int_t native_min_left_8 = ((native_min_6 * 707) / 1000);
      const elmc_int_t native_min_right_8 = ((native_min_6 - (native_min_6 / 6)) - (native_min_6 / 5));
      const elmc_int_t native_min_8 = (native_min_left_8 <= native_min_right_8) ? native_min_left_8 : native_min_right_8;
      const elmc_int_t native_min_left_9 = ((native_min_6 * 707) / 1000);
      const elmc_int_t native_min_right_9 = ((native_min_6 - direct_native_record_branch__then_y_8) - (native_min_6 / 5));
      const elmc_int_t native_min_9 = (native_min_left_9 <= native_min_right_9) ? native_min_left_9 : native_min_right_9;
      const elmc_int_t direct_native_record_branch__then_x_8 = native_min_9;
    """

    result = Hoist.drop_unused_native_minmax_decls(code)

    refute result =~ "native_min_8"
    refute result =~ "native_min_left_8"
    refute result =~ "native_min_right_8"
    assert result =~ "native_min_9"
    assert result =~ "native_min_left_9"
    assert result =~ "native_min_right_9"
  end

  test "drop_unused_native_minmax_decls keeps shared min hoists that are referenced" do
    code = """
      const elmc_int_t native_min_left_3 = direct_hoisted_int_3;
      const elmc_int_t native_min_right_3 = direct_hoisted_int_2;
      const elmc_int_t native_min_3 = (native_min_left_3 <= native_min_right_3) ? native_min_left_3 : native_min_right_3;
      const elmc_int_t direct_native_record_branch__then_x_3 = native_min_3 + 1;
    """

    result = Hoist.drop_unused_native_minmax_decls(code)

    assert result =~ "native_min_3"
    assert result =~ "native_min_left_3"
    assert result =~ "native_min_right_3"
  end
end
