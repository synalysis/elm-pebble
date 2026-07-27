defmodule Elmc.Backend.CCodegen.HelperParamsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.HelperParams

  test "unused_param_casts emits void casts for helper params not referenced in body" do
    params = [
      {"sample", {:boxed, "sample"}},
      {"used", {:native_int, "cx"}}
    ]

    body = "ElmcValue *out = NULL;\n  out = elmc_new_int(cx, 1);"

    assert HelperParams.unused_param_casts(params, body) == "(void)sample;"
  end

  test "unused_param_casts is empty when every param is referenced" do
    params = [{"x", {:native_int, "cx"}}]
    assert HelperParams.unused_param_casts(params, "return cx + 1;") == ""
  end
end
