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
end
