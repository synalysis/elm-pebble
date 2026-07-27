defmodule Elmc.CStubFunctionsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.C.StubFunctions

  test "missing_callee_stubs emits Elm.Kernel RC callee with inferred arity" do
  snippet =
    "Rc = elmc_fn_Elm_Kernel_Json_addField(&owned[2], owned[0], owned[1], (argc > 1 ? args[1] : NULL));"

    %{definitions: defs} = StubFunctions.missing_callee_stubs([snippet], [])

    assert defs =~ "static RC elmc_fn_Elm_Kernel_Json_addField"
    assert defs =~ "ElmcValue *arg2"
    assert defs =~ "RC_ERR_UNSUPPORTED"
  end

  test "missing_callee_stubs skips declared callees and only stubs Elm.Kernel names" do
    impl = """
    Rc = elmc_fn_Elm_Kernel_Json_addEntry(&owned[1], func);
    owned[0] = elmc_fn_Elm_JsArray_unsafeGet();
    """

    decl = "ElmcValue *elmc_fn_Task_command(void);\n"

    %{prototypes: protos, definitions: defs} = StubFunctions.missing_callee_stubs([impl], [decl])

    assert defs =~ "elmc_fn_Elm_Kernel_Json_addEntry"
    refute defs =~ "elmc_fn_Elm_JsArray_unsafeGet"
    refute protos =~ "elmc_fn_Task_command"
    assert defs =~ "elmc_fn_Elm_Kernel_Json_addEntry(ElmcValue **out, ElmcValue *arg0)"
  end

  test "missing_callee_stubs finds Kernel calls after UTF-8 string literals" do
    # Regression: String.slice on Regex byte indexes skipped callees once non-ASCII
    # bytes appeared earlier in the translation unit (Unicode corpus).
    impl = """
    static ElmcValue native_str = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, (void *)"ßΩ🙂", 8 };
    (void)native_str;
    Rc = elmc_fn_Elm_Kernel_Basics_and(&owned[2], elmc_new_bool_take(1), elmc_new_bool_take(0));
    return elmc_fn_Elm_Kernel_JsArray_initialize(elmc_new_int_take(1), elmc_new_int_take(0), fn);
    """

    %{prototypes: protos, definitions: defs} = StubFunctions.missing_callee_stubs([impl], [])

    assert protos =~ "elmc_fn_Elm_Kernel_Basics_and"
    assert protos =~ "elmc_fn_Elm_Kernel_JsArray_initialize"
    assert defs =~ "elmc_fn_Elm_Kernel_Basics_and"
    assert defs =~ "elmc_fn_Elm_Kernel_JsArray_initialize"
  end
end
