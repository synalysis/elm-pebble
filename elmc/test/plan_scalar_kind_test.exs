defmodule Elmc.PlanScalarKindTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.ScalarKind

  test "kind table covers Int, Bool, and Float" do
    assert ScalarKind.kinds() == [:int, :bool, :float]
    assert ScalarKind.from_elm_type("Int") == :int
    assert ScalarKind.from_elm_type("Bool") == :bool
    assert ScalarKind.from_elm_type("Float") == :float
    assert ScalarKind.from_elm_type("String") == nil
  end

  test "C type, peel, box, and local names are kind-parameterized" do
    assert ScalarKind.c_type(:int) == "elmc_int_t"
    assert ScalarKind.c_type(:bool) == "bool"
    assert ScalarKind.c_type(:float) == "double"

    assert ScalarKind.peel(:int) == "elmc_as_int"
    assert ScalarKind.peel(:bool) == "elmc_as_bool"
    assert ScalarKind.peel(:float) == "elmc_as_float"

    assert ScalarKind.box(:int) == "elmc_new_int"
    assert ScalarKind.box(:bool) == "elmc_new_bool"
    assert ScalarKind.box(:float) == "elmc_new_float"

    assert ScalarKind.local_name(:int, 3) == "plan_native_int_3"
    assert ScalarKind.local_name(:bool, 3) == "plan_native_bool_3"
    assert ScalarKind.local_name(:float, 3) == "plan_native_float_3"

    assert ScalarKind.c_out_type(:native_float) == "double *out"
    assert ScalarKind.native_return?(:native_float)
    refute ScalarKind.native_return?(:native_int_pair)
    assert ScalarKind.native_or_pair?(:native_int_pair)
  end
end
