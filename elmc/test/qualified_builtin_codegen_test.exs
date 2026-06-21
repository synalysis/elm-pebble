defmodule Elmc.QualifiedBuiltinCodegenTest do
  use ExUnit.Case

  alias Elmc.Backend.CCodegen.Hoist
  alias Elmc.Test.CCodegenExtract

  test "qualified Basics operators are lowered as builtins" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/qualified_builtin_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_c =~ "elmc_fn_Basics___mul__"
    refute generated_c =~ "elmc_fn_Basics___add__"
    refute generated_c =~ "elmc_fn_Basics___idiv__"
  end

  test "complete Basics numeric surface lowers to runtime builtins" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/complete_basics_project", __DIR__)
    out_dir = Path.expand("tmp/complete_basics_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), complete_basics_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    refute generated_c =~ "elmc_fn_Basics_"
    assert generated_c =~ "elmc_basics_sqrt"
    assert generated_c =~ "elmc_basics_log_base"
    assert generated_c =~ "elmc_basics_from_polar"

    File.write!(
      Path.join(out_dir, "c/complete_basics_harness.c"),
      "int main(void) { return 0; }\n"
    )

    cc = System.find_executable("cc") || System.find_executable("gcc")
    assert is_binary(cc)

    {compile_out, compile_code} =
      System.cmd(
        cc,
        [
          "-std=c11",
          "-Wall",
          "-Wextra",
          "-Iruntime",
          "-Iports",
          "-Ic",
          "runtime/elmc_runtime.c",
          "ports/elmc_ports.c",
          "c/elmc_generated.c",
          "c/elmc_worker.c",
          "c/elmc_pebble.c",
          "c/complete_basics_harness.c",
          "-lm",
          "-o",
          "complete_basics_harness"
        ],
        cd: out_dir,
        stderr_to_stdout: true
      )

    assert compile_code == 0, compile_out
  end

  test "operator sections and list cons compile to runtime builtins" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/operator_section_cons_project", __DIR__)
    out_dir = Path.expand("tmp/operator_section_cons_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), operator_section_cons_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main"
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    refute generated_c =~ "elmc_fn_Main___neq__"
    refute generated_c =~ "elmc_fn_List_cons"
    assert generated_c =~ "elmc_list_cons"
    File.write!(Path.join(out_dir, "c/operator_section_cons_harness.c"), minimal_harness_source())

    cc = System.find_executable("cc") || System.find_executable("gcc")
    assert is_binary(cc)

    {compile_out, compile_code} =
      System.cmd(
        cc,
        [
          "-std=c11",
          "-Wall",
          "-Wextra",
          "-Iruntime",
          "-Iports",
          "-Ic",
          "runtime/elmc_runtime.c",
          "ports/elmc_ports.c",
          "c/elmc_generated.c",
          "c/elmc_worker.c",
          "c/elmc_pebble.c",
          "c/operator_section_cons_harness.c",
          "-lm",
          "-o",
          "operator_section_cons_harness"
        ],
        cd: out_dir,
        stderr_to_stdout: true
      )

    assert compile_code == 0, compile_out
  end

  test "typed Int arguments feed native record literals without retain boxing" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/typed_int_arg_project", __DIR__)
    out_dir = Path.expand("tmp/typed_int_arg_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> typed_int_arg_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    typed_bounds_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_typedBounds_native")

    assert typed_bounds_body =~ ~r/elmc_record_new_values_(?:ints_)?take/
    refute typed_bounds_body =~ "elmc_retain(x)"
    refute typed_bounds_body =~ "elmc_retain(y)"

    typed_access_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_typedBoundsAccess_native")

    assert typed_access_body =~ "elmc_record_get_index("

    assert typed_access_body =~
             ~r/elmc_record_get_index\(tmp_\d+, (?:ELMC_FIELD_MAIN_TYPEDBOUNDS_X|2 \/\* x \*\/)\)/
    refute typed_access_body =~ "elmc_record_get(tmp_"
  end

  test "native Int case subjects avoid boxed pattern checks" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_int_case_project", __DIR__)
    out_dir = Path.expand("tmp/native_int_case_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> native_int_case_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    native_case_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeIntCase")

    assert native_case_body =~ "const elmc_int_t native_let_caseSubject_"
    assert native_case_body =~ ~r/const elmc_int_t native_lut_\d+\[4\] = \{ 1, 2, 3, 4 \};/
    assert native_case_body =~ ~r/native_case_\d+ = native_lut_\d+\[\(\(native_let_caseSubject_/
    refute native_case_body =~ "switch (native_let_caseSubject_"
    refute native_case_body =~ " = elmc_int_zero();\n  switch"
    refute native_case_body =~ "elmc_new_int("
    refute native_case_body =~ "elmc_release(tmp_"
    refute native_case_body =~ "->tag == ELMC_TAG_INT"
    refute native_case_body =~ "elmc_as_int(native_let_caseSubject_"
    refute native_case_body =~ "elmc_new_int(native_mod_"
  end

  test "native Int case string branches assign result directly" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_int_case_string_project", __DIR__)
    out_dir = Path.expand("tmp/native_int_case_string_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> native_int_case_string_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    case_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeIntCaseString")

    assert case_body =~ "switch (month)"
    assert case_body =~ "case 1:"
    assert case_body =~ " = elmc_new_string_take(\"Jan\");"
    assert case_body =~ "case 2:"
    assert case_body =~ " = elmc_new_string_take(\"Feb\");"

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_new_string\(\"Jan\"\);\s+tmp_\d+ = tmp_\d+;/,
             case_body
           )
  end

  test "boxed constructor case string branches assign result directly" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/boxed_constructor_case_string_project", __DIR__)
    out_dir = Path.expand("tmp/boxed_constructor_case_string_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> boxed_constructor_case_string_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    case_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_boxedDirectionString")

    assert case_body =~ "switch (case_msg_tag_"
    assert case_body =~ "case "
    assert case_body =~ " = elmc_new_string_take(\"N\");"
    assert case_body =~ " = elmc_new_string_take(\"S\");"
    refute Regex.match?(~r/else if \(.*->tag == ELMC_TAG_TUPLE2/, case_body)
    refute Regex.match?(~r/elmc_release\(tmp_\d+\);\s+tmp_\d+ = tmp_\d+;/, case_body)

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_new_string\(\"N\"\);\s+tmp_\d+ = tmp_\d+;/,
             case_body
           )
  end

  test "Basics.round on bound trig product stays native in scoring-style expressions" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/trig_round_native_project", __DIR__)
    out_dir = Path.expand("tmp/trig_round_native_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> trig_round_native_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body =
      generated_c
      |> String.split("static elmc_int_t elmc_fn_Main_trigRoundScore_native")
      |> List.last()

    [fn_body | _] = String.split(body, "static ElmcValue *elmc_fn_", parts: 2)

    assert fn_body =~ "elmc_basics_sin_double((double)degrees)"
    refute fn_body =~ "elmc_new_int(elmc_basics_round("
  end

  test "boolean record fields in conditions use native bool accessors" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_bool_field_project", __DIR__)
    out_dir = Path.expand("tmp/native_bool_field_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> native_bool_field_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    native_bool_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeBoolField")

    assert native_bool_body =~ "if (ELMC_RECORD_GET_INDEX_BOOL(model,"
    refute native_bool_body =~ "elmc_record_get(model, \"isRound\")"
    refute native_bool_body =~ "elmc_as_int(tmp_"

    native_bool_helper_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeBoolHelperColor")

    assert native_bool_helper_body =~ "elmc_as_bool(tmp_"
    assert native_bool_helper_body =~ "ElmcValue *tmp_"
    assert native_bool_helper_body =~ " = elmc_retain(tmp_"
    refute native_bool_helper_body =~ "if (elmc_as_int(tmp_"
    refute native_bool_helper_body =~ " ? elmc_retain(tmp_"
    assert native_bool_helper_body =~ "native_if_3 = 192;"
    assert native_bool_helper_body =~ "native_if_3 = 255;"

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_new_int\(192\);\s+tmp_\d+ = tmp_\d+;/,
             native_bool_helper_body
           )

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_int_zero\(\);\s+if \(native_b_\d+\)/,
             native_bool_helper_body
           )

    native_bool_mixed_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeBoolMixedBranches")

    assert native_bool_mixed_body =~ "bool native_bool_if_"
    assert native_bool_mixed_body =~ "if ((value < 0))"
    assert native_bool_mixed_body =~ "native_bool_if_"
    assert native_bool_mixed_body =~ " = true;"
    assert native_bool_mixed_body =~ "elmc_value_equal("
    refute native_bool_mixed_body =~ "elmc_new_int(1)"
    refute Regex.match?(~r/(?:const )?bool native_bool_if_\d+ = false;\s+if/, native_bool_mixed_body)
    refute Regex.match?(~r/elmc_as_int\(tmp_\d+\) != 0/, native_bool_mixed_body)

    native_bool_maybe_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeBoolMaybeBranchReuse")

    assert native_bool_maybe_body =~ "if (flag)"
    assert native_bool_maybe_body =~ "ElmcValue *tmp_1 = NULL;"
    refute native_bool_maybe_body =~ "ElmcValue *tmp_1 = elmc_int_zero();"
  end

  test "boxed Int variables in equality are not coerced to Bool" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/boxed_int_equality_project", __DIR__)
    out_dir = Path.expand("tmp/boxed_int_equality_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> boxed_int_equality_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_c =~ "elmc_as_bool(i) == elmc_as_bool(index)"
    assert generated_c =~ "elmc_value_equal"
  end

  test "integer lets are not promoted to Float in Int arithmetic" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/integer_let_arithmetic_project", __DIR__)
    out_dir = Path.expand("tmp/integer_let_arithmetic_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> integer_let_arithmetic_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    integer_let_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_integerLetArithmetic")

    refute integer_let_body =~ "native_float_headerBottom"
    refute integer_let_body =~ "elmc_new_float"
    assert integer_let_body =~ "native_let_headerBottom_"
    assert integer_let_body =~ "(2 * (height - native_let_headerBottom_"
  end

  test "min over record Int fields lowers to native C comparison" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_min_record_fields_project", __DIR__)
    out_dir = Path.expand("tmp/native_min_record_fields_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> native_min_record_fields_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    native_min_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeMinRecordFields")

    assert native_min_body =~
             "ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_NATIVEMINRECORDMODEL_SCREENW)"

    assert native_min_body =~
             "ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_NATIVEMINRECORDMODEL_SCREENH)"
    assert native_min_body =~ "native_min_"
    refute native_min_body =~ "elmc_basics_min"
    refute native_min_body =~ "elmc_record_get(model, \"screenW\")"
    refute native_min_body =~ "elmc_record_get(model, \"screenH\")"
  end

  test "record field indices follow alphabetical record literal order" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/record_field_order_project", __DIR__)
    out_dir = Path.expand("tmp/record_field_order_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> record_field_order_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_watchModelArea")

    assert body =~ "ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_WATCHMODEL_SCREENW)"
    assert body =~ "ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_WATCHMODEL_SCREENH)"
  end

  test "String.fromInt over native Int avoids temporary boxed integer" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_string_from_int_project", __DIR__)
    out_dir = Path.expand("tmp/native_string_from_int_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> native_string_from_int_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    native_string_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeStringFromInt_native")

    assert native_string_body =~ "elmc_string_from_native_int_take((value + 1))"
    refute native_string_body =~ "elmc_new_int((value + 1))"
    refute native_string_body =~ "elmc_string_from_int"

    native_append_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeStringAppend_native")

    assert native_append_body =~ ~r/elmc_string_append_native(_take)?\(\"0\", native_string_/
    assert native_append_body =~ "snprintf(native_string_buf_"
    refute native_append_body =~ "elmc_new_string(\"0\")"
    refute native_append_body =~ "elmc_string_from_native_int(value)"
    refute native_append_body =~ "elmc_append("
  end

  test "boxed String if lets avoid default initialization and nullable retain fallback" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/boxed_string_if_project", __DIR__)
    out_dir = Path.expand("tmp/boxed_string_if_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> boxed_string_if_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    boxed_string_if_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_boxedStringIf")

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_int_zero\(\);\s+if \(\(value < 0\)\)/,
             boxed_string_if_body
           )

    refute Regex.match?(
             ~r/elmc_release\(tmp_\d+\);\s+tmp_\d+ = tmp_\d+;/,
             boxed_string_if_body
           )

    refute boxed_string_if_body =~ "? elmc_retain(tmp_"
    refute boxed_string_if_body =~ "elmc_append("
    refute boxed_string_if_body =~ "&& tmp_"

    assert boxed_string_if_body =~ "snprintf(native_string_buf_"
    assert boxed_string_if_body =~ ~r/elmc_string_append_native(_take)?\(native_string_/
  end

  test "Maybe.withDefault Int feeds String.fromInt without boxed default or result" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_maybe_default_string_project", __DIR__)
    out_dir = Path.expand("tmp/native_maybe_default_string_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")

    source =
      main_path
      |> File.read!()
      |> String.replace(
        "import Json.Decode as Decode",
        "import Dict\nimport Json.Decode as Decode"
      )

    File.write!(main_path, source <> native_maybe_default_string_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    maybe_string_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeMaybeDefaultString")

    assert maybe_string_body =~ "native_maybe_default_"
    assert maybe_string_body =~ "elmc_record_get_index_maybe_int(model, 0 /* batteryLevel */, 0)"
    assert maybe_string_body =~ "elmc_string_from_native_int_take(native_maybe_default_"
    refute maybe_string_body =~ "elmc_record_get(model, \"batteryLevel\")"
    refute maybe_string_body =~ "elmc_int_zero()"
    refute maybe_string_body =~ "elmc_maybe_with_default("
    refute maybe_string_body =~ "elmc_string_from_int"

    maybe_arg_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeMaybeDefaultStringArg")

    assert maybe_arg_body =~ "native_maybe_default_"
    assert maybe_arg_body =~ "elmc_record_get_index_maybe_int(model, 0 /* batteryLevel */, 0)"
    assert maybe_arg_body =~ "elmc_string_from_native_int_take(native_maybe_default_"
    refute maybe_arg_body =~ "elmc_record_get(model, \"batteryLevel\")"
    refute maybe_arg_body =~ "elmc_int_zero()"
    refute maybe_arg_body =~ "elmc_maybe_with_default("
    refute maybe_arg_body =~ "elmc_string_from_int"

    maybe_head_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeMaybeDefaultHeadString")

    assert maybe_head_body =~ "elmc_list_head_with_default_int(0,"
    assert maybe_head_body =~ "elmc_string_from_native_int_take(native_maybe_default_"
    refute maybe_head_body =~ "elmc_list_head("
    refute maybe_head_body =~ "elmc_maybe_with_default_int("

    maybe_dict_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeMaybeDefaultDictString")

    assert maybe_dict_body =~ "elmc_dict_get_with_default_int(0, key,"
    assert maybe_dict_body =~ "elmc_string_from_native_int_take(native_maybe_default_"
    refute maybe_dict_body =~ "elmc_dict_get("
    refute maybe_dict_body =~ "elmc_maybe_with_default_int("
  end

  test "typed Bool helper arguments stay native through control flow" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_bool_arg_project", __DIR__)
    out_dir = Path.expand("tmp/native_bool_arg_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> native_bool_arg_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~
             "static ElmcValue *elmc_fn_Main_nativeBoolBranch_native(const bool enabled, const elmc_int_t value)" or
             generated_c =~
               "static ElmcValue *elmc_fn_Main_nativeBoolBranch_native(const elmc_int_t enabled, const elmc_int_t value)"

    assert generated_c =~ "elmc_as_bool(args[0])"

    call_body =
      generated_c
      |> String.split("static ElmcValue *elmc_fn_Main_nativeBoolCall_native")
      |> List.last()

    [native_call_body | _rest] = String.split(call_body, "static ElmcValue *elmc_fn_", parts: 2)

    assert native_call_body =~ "elmc_fn_Main_nativeBoolBranch_native(enabled, 7)"
    refute native_call_body =~ "elmc_new_bool(enabled)"

    refute generated_c =~ "elmc_fn_Main_nativeBoolCaptured_native"

    assert generated_c =~
             "static elmc_int_t elmc_fn_Main_nativeBoolBoxedUse_native(ElmcValue * const enabled, const elmc_int_t value)"

    native_compare_branch_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeBoolCompareBranch_native")

    assert native_compare_branch_body =~ "if ((left == right))"
    refute native_compare_branch_body =~ "elmc_new_bool(left == right)"
    refute native_compare_branch_body =~ "elmc_value_equal"

    native_compare_call_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeBoolCompareCall")

    assert native_compare_call_body =~
             "elmc_fn_Main_nativeBoolBranch_native(!(((bool)elmc_as_bool(left) == (bool)elmc_as_bool(right))), 3)" or
             native_compare_call_body =~
               "elmc_fn_Main_nativeBoolBranch_native(!((elmc_as_bool(left) == elmc_as_bool(right))), 3)"

    refute native_compare_call_body =~ "elmc_new_bool"
    refute native_compare_call_body =~ "elmc_value_equal"
  end

  test "let Int expressions passed to native helper Int args stay unboxed" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_helper_arg_let_project", __DIR__)
    out_dir = Path.expand("tmp/native_helper_arg_let_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> native_helper_arg_let_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    native_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeHelperArgLet_native")

    assert native_body =~ "native_let_moonPhaseY_"
    assert native_body =~ "native_max_"
    assert native_body =~ "native_let_moonPhaseY_1 + native_max_"
    refute native_body =~ "elmc_new_int((cy +"

    call_body =
      generated_c
      |> String.split("static ElmcValue *elmc_fn_Main_typedIntReturnReuse")
      |> List.last()

    [typed_call_body | _rest] = String.split(call_body, "static ElmcValue *elmc_fn_", parts: 2)

    assert typed_call_body =~ "ElmcValue *tmp_"
    assert typed_call_body =~ "elmc_fn_Main_opaqueStringLength"
    assert typed_call_body =~ "const elmc_int_t native_let_hours_"
    assert typed_call_body =~ "// inlined Main.nativeIntSink" or
             typed_call_body =~ "elmc_fn_Main_nativeIntSink_native(native_let_hours_"
    refute typed_call_body =~ " ? elmc_as_int(tmp_"
    refute typed_call_body =~ "elmc_new_int((tmp_"
  end

  test "enum arguments compare constructor tags natively" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/enum_compare_project", __DIR__)
    out_dir = Path.expand("tmp/enum_compare_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> enum_compare_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    enum_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_enumUnitString")

    assert enum_body =~ "ELMC_UNION_MILESPERHOUR" or enum_body =~ "elmc_as_int(unit) == 2"
    refute enum_body =~ "elmc_retain(unit)"
    refute enum_body =~ "elmc_value_equal"
    refute enum_body =~ "elmc_new_int(2)"
  end

  test "Basics abs and negate over native Int avoid boxed runtime calls" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_abs_negate_project", __DIR__)
    out_dir = Path.expand("tmp/native_abs_negate_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> native_abs_negate_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    native_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeAbsNegate_native")

    assert native_body =~ "native_abs_arg_"
    assert native_body =~ "native_negate_arg_"
    assert native_body =~ " < 0 ? -"
    refute native_body =~ "elmc_basics_abs"
    refute native_body =~ "elmc_basics_negate"
    refute native_body =~ "elmc_new_int((phaseE6 - 500000))"
  end

  test "division by nonzero literal omits denominator guard" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_literal_division_project", __DIR__)
    out_dir = Path.expand("tmp/native_literal_division_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> native_literal_division_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    native_div_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeLiteralDivision_native")

    assert native_div_body =~ "elmc_string_from_native_int_take(elmc_int_idiv((value * 328), 100))"
    refute native_div_body =~ "native_den_"
    refute native_div_body =~ "== 0 ? 0"
  end

  test "record fields from helper calls inline helper body once per field" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/helper_record_field_project", __DIR__)
    out_dir = Path.expand("tmp/helper_record_field_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> helper_record_field_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    use_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_helperRecordFieldOps_commands_append_native")

    refute use_body =~ "elmc_fn_Main_helperRecordFieldBounds"
    assert use_body =~ "scene_cmd.p0 = (x + 1);"
    assert use_body =~ "scene_cmd.p3 = 12;"
  end

  test "typed Color and String arguments use native direct command parameters" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_text_arg_project", __DIR__)
    out_dir = Path.expand("tmp/native_text_arg_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")

    main_source =
      main_path
      |> File.read!()
      |> String.replace(
        "import Pebble.Ui.Color as PebbleColor",
        """
        import Pebble.Ui.Color as PebbleColor
        import Pebble.Ui.Color as Color
        import Pebble.Ui.Color exposing (Color)
        """
        |> String.trim_trailing()
      )

    File.write!(main_path, main_source <> native_text_arg_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~
             "static RC elmc_fn_Main_nativeTextAt_commands_append_native(const elmc_int_t color, const char * const value"

    # Single-call render helpers are inlined into their sole caller (no separate def).
    refute generated_c =~ "elmc_fn_Main_nativeTextAtAlias_commands_append_native"
    refute generated_c =~ "elmc_fn_Main_nativeTextAtExplicitAlias_commands_append_native"
    refute generated_c =~ "elmc_fn_Main_nativeTextAtExposedType_commands_append_native"

    alias_if_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeTextAliasIf_commands_append")

    assert alias_if_body =~ "ELMC_RENDER_OP_TEXT"

    literal_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeTextLiteral_commands_append")

    assert literal_body =~
             "elmc_fn_Main_nativeTextAt_commands_append_native(ELMC_COLOR_WHITE, \"Direct\""

    refute literal_body =~ "elmc_new_string(\"Direct\")"
    refute literal_body =~ "elmc_new_int(255)"

    native_let_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeTextLet_commands_append")

    assert native_let_body =~ "char native_string_buf_"
    assert native_let_body =~ "snprintf(native_string_buf_"
    assert native_let_body =~ "? \"Zero\" : native_string_"
    refute native_let_body =~ "elmc_new_string(\"Zero\")"
    refute native_let_body =~ "elmc_string_from_native_int(value)"

    native_alias_if_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeTextAliasIf_commands_append")

    assert native_alias_if_body =~ "ELMC_COLOR_BLACK"
    assert native_alias_if_body =~ "ELMC_COLOR_WHITE"
    refute native_alias_if_body =~ "elmc_new_int(192)"
    refute native_alias_if_body =~ "elmc_new_int(255)"

    native_explicit_alias_if_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeTextExplicitAliasIf_commands_append")

    assert native_explicit_alias_if_body =~ "ELMC_COLOR_BLACK"
    assert native_explicit_alias_if_body =~ "ELMC_COLOR_WHITE"
    refute native_explicit_alias_if_body =~ "elmc_new_int(192)"
    refute native_explicit_alias_if_body =~ "elmc_new_int(255)"

    native_exposed_type_if_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeTextExposedTypeIf_commands_append")

    assert native_exposed_type_if_body =~ "ELMC_COLOR_BLACK"
    assert native_exposed_type_if_body =~ "ELMC_COLOR_WHITE"
    refute native_exposed_type_if_body =~ "elmc_new_int(192)"
    refute native_exposed_type_if_body =~ "elmc_new_int(255)"

    native_bounds_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeTextBounds_commands_append")

    assert native_bounds_body =~
             "scene_cmd.p1 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_X)"

    assert native_bounds_body =~
             "scene_cmd.p2 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_Y)"

    assert native_bounds_body =~
             "scene_cmd.p3 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_W)"

    assert native_bounds_body =~
             "scene_cmd.p4 = ELMC_RECORD_GET_INDEX_INT(bounds, ELMC_FIELD_PEBBLE_UI_RECT_H)"

    refute native_bounds_body =~ "scene_cmd.p1 = 0;"
    refute native_bounds_body =~ "scene_cmd.p3 = 0;"

    native_helper_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeTextFromHelper_commands_append")

    assert native_helper_body =~ "ElmcValue *tmp_"
    assert native_helper_body =~ "const char *native_string_"
    assert native_helper_body =~ "(const char *)tmp_"
    refute native_helper_body =~ "ELMC_TAG_LIST"
    refute native_helper_body =~ "elmc_string_from_list"
  end

  test "text options encode alignment and overflow in direct draw commands" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/text_options_project", __DIR__)
    out_dir = Path.expand("tmp/text_options_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, text_options_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~
             ~r/direct_hoisted_int_\d+ = \(ELMC_TEXT_ALIGN_LEFT \+ \(ELMC_TEXT_OVERFLOW_WORD_WRAP \* \(1 << ELMC_TEXT_OVERFLOW_SHIFT\)\)\)/

    assert generated_c =~
             ~r/direct_hoisted_int_\d+ = \(ELMC_TEXT_ALIGN_CENTER \+ \(ELMC_TEXT_OVERFLOW_TRAILING_ELLIPSIS \* \(1 << ELMC_TEXT_OVERFLOW_SHIFT\)\)\)/

    assert generated_c =~
             ~r/direct_hoisted_int_\d+ = \(ELMC_TEXT_ALIGN_RIGHT \+ \(ELMC_TEXT_OVERFLOW_FILL \* \(1 << ELMC_TEXT_OVERFLOW_SHIFT\)\)\)/

    assert generated_c =~ ~r/scene_cmd\.p5 = direct_hoisted_int_\d+/

    assert generated_c =~ "scene_cmd.text[0] = 'L';"
    assert generated_c =~ "scene_cmd.text[4] = '\\0';"
    refute generated_c =~ "const char *direct_text = \"Left\";"
  end

  test "direct command Int lets stay native inside bounds records" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_native_let_bounds_project", __DIR__)
    out_dir = Path.expand("tmp/direct_native_let_bounds_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> direct_native_let_bounds_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    use_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_directNativeLetBounds_commands_append_native")

    assert use_body =~ "elmc_int_t direct_native_let_x_"
    assert use_body =~ "elmc_int_t direct_native_let_y_"
    assert use_body =~ "scene_cmd.p1 = direct_native_let_x_"
    assert use_body =~ "scene_cmd.p2 = direct_native_let_y_"
    refute use_body =~ "elmc_new_int((screenW - 64))"
    refute use_body =~ "elmc_new_int((screenH - 36))"
  end

  test "direct command Int lets stay native for circle radius args" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_native_let_circle_radius_project", __DIR__)
    out_dir = Path.expand("tmp/direct_native_let_circle_radius_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> direct_native_let_circle_radius_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body =
      generated_c
      |> String.split(
        "static RC elmc_fn_Main_directNativeLetCircleRadius_commands_append_native"
      )
      |> List.last()

    [use_body | _rest] = String.split(body, "int elmc_fn_", parts: 2)

    assert use_body =~ ~r/direct_native_let_radius_\d+ = native_max_/
    assert use_body =~ ~r/scene_cmd\.p2 = direct_native_let_radius_/
    refute use_body =~ "elmc_basics_max("
  end

  test "direct command radius lets hoist for analog marker hand positions" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_native_let_analog_markers_project", __DIR__)
    out_dir = Path.expand("tmp/direct_native_let_analog_markers_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> direct_native_let_analog_markers_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    use_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_directNativeLetAnalogMarkers_commands_append")

    assert use_body =~ ~r/direct_native_let_radius_\d+ = native_max_/
    assert use_body =~ "direct_native_let_markerTopX_"
    assert use_body =~ ~r/elmc_int_idiv\(\(direct_hoisted_int_\d+ \* direct_native_let_radius_\d+\), 1000\)/
    refute use_body =~ "elmc_fn_Main_handX_native"
    refute use_body =~ "elmc_new_int(native_max"
    refute use_body =~ "elmc_fn_Main_unit12X_native"
    refute use_body =~ "elmc_as_int(tmp_"
  end

  test "native lookup tables return elmc_int_t without boxing case branches" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_unit12_lookup_project", __DIR__)
    out_dir = Path.expand("tmp/native_unit12_lookup_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> native_unit12_lookup_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body =
      generated_c
      |> String.split("static elmc_int_t elmc_fn_Main_unit12X_native")
      |> List.last()

    [unit12_body | _rest] = String.split(body, "static ElmcValue *elmc_fn_Main_unit12Y", parts: 2)

    assert unit12_body =~ ~r/const elmc_int_t native_lut_\d+\[\d+\] = \{/
    assert unit12_body =~ "500"
    assert unit12_body =~ "1000"
    assert unit12_body =~ "-500"
    refute unit12_body =~ "switch (native_let_caseSubject_"
    refute unit12_body =~ "elmc_new_int("
    refute unit12_body =~ "elmc_int_zero()"
  end

  test "direct render folds literal unit12 lookups and hoists variable ones" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_unit12_dedup_project", __DIR__)
    out_dir = Path.expand("tmp/direct_unit12_dedup_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> direct_unit12_dedup_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    use_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_directUnit12Dedup_commands_append")

    assert use_body =~ "direct_hoisted_int_"
    assert use_body =~ ~r/const elmc_int_t direct_hoisted_int_\d+ = 0;/
    assert use_body =~ ~r/const elmc_int_t direct_hoisted_int_\d+ = -1000;/

    assert use_body =~
             ~r/direct_native_let_markerTopX_\d+ = direct_hoisted_int_\d+;\n.*direct_native_let_markerTopY_\d+ = direct_hoisted_int_\d+;/s

    lut_count =
      use_body
      |> String.split("const elmc_int_t native_lut_")
      |> length()
      |> Kernel.-(1)

    assert lut_count <= 4
    refute use_body =~ "switch (native_let_caseSubject_"
  end

  test "curried let-bound Ui.text helpers keep string args boxed in lambdas" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/calendar_label_helper_project", __DIR__)
    out_dir = Path.expand("tmp/calendar_label_helper_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> calendar_label_helper_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_c =~
             "const elmc_int_t text_ = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;"

    assert generated_c =~ "ElmcValue *text_ = (argc > 0) ? args[0] : NULL;"
    assert generated_c =~ "elmc_new_string_take(\"Next event\")"
  end

  test "record helper inlining does not recursively substitute self-referential offsets" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/self_referential_substitution_project", __DIR__)
    out_dir = Path.expand("tmp/self_referential_substitution_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> self_referential_substitution_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "static RC elmc_fn_Main_selfReferentialOps_commands_append_native"
    assert generated_c =~ "scene_cmd.p0 = ((x - 1) - 1);"
  end

  test "direct command Int if lets stay native through both branches" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_native_if_let_project", __DIR__)
    out_dir = Path.expand("tmp/direct_native_if_let_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> direct_native_if_let_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    use_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_directNativeIfLet_commands_append_native")

    assert use_body =~ "elmc_int_t native_if_"
    assert use_body =~ "native_negate_"
    assert use_body =~ "scene_cmd.p0 = (cx + direct_native_let_offset_"
    refute Regex.match?(~r/elmc_int_t native_if_\d+ = 0;/, use_body)
    refute use_body =~ "ElmcValue *tmp_"
    refute use_body =~ "elmc_basics_negate"
  end

  test "direct command Bool conditions avoid retained condition temporaries" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_native_bool_condition_project", __DIR__)
    out_dir = Path.expand("tmp/direct_native_bool_condition_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> direct_native_bool_condition_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    condition_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_directNativeBoolCondition_commands_append")

    assert condition_body =~ "if ((bool)elmc_as_bool(enabled))" or
             condition_body =~ "if (elmc_as_bool(enabled))"
    assert condition_body =~ "elmc_draw_cmd_init(&scene_cmd, ELMC_RENDER_OP_CLEAR)"
    refute condition_body =~ "elmc_draw_cmd_init(&scene_cmd, 2)"
    refute condition_body =~ "elmc_retain(enabled)"
    refute condition_body =~ "elmc_release(enabled)"
    refute condition_body =~ "ElmcValue *tmp_"

    empty_then_condition_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_directEmptyThenCondition_commands_append")

    assert empty_then_condition_body =~ "if (!((bool)elmc_as_bool(enabled)))" or
             empty_then_condition_body =~ "if (!(elmc_as_bool(enabled)))"
    refute empty_then_condition_body =~ "} else {"

    typed_int_direct_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_directTypedIntResultReuse_commands_append")

    assert typed_int_direct_body =~ "elmc_fn_Main_opaqueStringLength"
    assert typed_int_direct_body =~ "elmc_as_int(tmp_"

    refute Regex.match?(
             ~r/tmp_\d+ \? elmc_retain\(tmp_\d+\) : elmc_int_zero\(\)/,
             typed_int_direct_body
           )
  end

  test "wildcard case branches do not emit constant if conditions" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/wildcard_case_condition_project", __DIR__)
    out_dir = Path.expand("tmp/wildcard_case_condition_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> wildcard_case_condition_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    case_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_wildcardCaseCondition")

    refute case_body =~ "if (1)"
    refute case_body =~ "else if (1)"
    assert case_body =~ "else {"

    direct_body =
      generated_c
      |> String.split("static RC elmc_fn_Main_wildcardCaseConditionOps_commands_append")
      |> List.last()

    [direct_case_body | _rest] = String.split(direct_body, "int elmc_fn_", parts: 2)

    refute direct_case_body =~ "if (1)"
    refute direct_case_body =~ "else if (1)"
    assert direct_case_body =~ "else {"
  end

  test "direct command Maybe.withDefault Int stays native through helper args" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_maybe_default_helper_arg_project", __DIR__)
    out_dir = Path.expand("tmp/direct_maybe_default_helper_arg_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> direct_maybe_default_helper_arg_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    helper_arg_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_directMaybeDefaultHelperArg_commands_append")

    assert helper_arg_body =~ "elmc_record_get_index_maybe_int(model, 0 /* moonsetMin */, 720)"
    assert helper_arg_body =~ "= (direct_native_let_moonset_"
    refute helper_arg_body =~ "elmc_new_int(720)"
    refute helper_arg_body =~ "elmc_record_get(model, \"moonsetMin\")"
    refute helper_arg_body =~ "elmc_maybe_with_default"
    refute helper_arg_body =~ "elmc_fn_Main_helperAngle_native"
    assert helper_arg_body =~ "// inlined Main.helperAngle"

    sun_body =
      generated_c
      |> String.split("static RC elmc_fn_Main_directSunWindowFields_commands_append")
      |> List.last()

    [sun_window_body | _rest] = String.split(sun_body, "int elmc_fn_", parts: 2)

    assert sun_window_body =~ "ELMC_FIELD_MAIN_DIRECTSUNWINDOW_SUNRISEMIN"
    assert sun_window_body =~ "ELMC_FIELD_MAIN_DIRECTSUNWINDOW_SUNSETMIN"
    assert sun_window_body =~ "direct_native_let_sunrise_"
    assert sun_window_body =~ "direct_native_let_sunset_"
    refute sun_window_body =~ "elmc_record_get_int("
  end

  test "lambda Int args bind once as native ints when only used natively" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_lambda_arg_project", __DIR__)
    out_dir = Path.expand("tmp/native_lambda_arg_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> native_lambda_arg_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_string_from_native_int"
    assert generated_c =~ "% 2"
    refute generated_c =~ "elmc_new_int(elmc_as_int(list_map_head"
  end

  test "boxed Int record fields compare natively without Basics.compare" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_boxed_record_compare_project", __DIR__)
    out_dir = Path.expand("tmp/native_boxed_record_compare_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> native_boxed_record_compare_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    compare_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_nativeBoxedRecordCompare")

    refute compare_body =~ "elmc_basics_compare"
    refute compare_body =~ "elmc_new_int(720)"
    assert compare_body =~ "ELMC_RECORD_GET_INDEX_INT"
    assert compare_body =~ "native_let_sunrise_"
    assert compare_body =~ " < 720"
    assert compare_body =~ " == 720"
  end

  test "native-only callees omit boxed wrappers in stripped builds" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_only_wrapper_project", __DIR__)
    out_dir = Path.expand("tmp/native_only_wrapper_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), native_only_wrapper_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               prune_native_wrappers: true
             })

    generated_h = File.read!(Path.join(out_dir, "c/elmc_generated.h"))
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_h =~ "elmc_fn_Main_nativeOnlyHelper("
    refute generated_c =~ "ElmcValue *elmc_fn_Main_nativeOnlyHelper(ElmcValue **args, int argc)"

    assert generated_c =~
             "static elmc_int_t elmc_fn_Main_nativeOnlyHelper_native(const elmc_int_t value)"

    assert generated_c =~ "nativeOnlyHelper_native"
    assert generated_c =~ "direct_hoisted_int_"
  end

  test "native callees forward-declare non-native top-level constants in stripped builds" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/native_constant_forward_decl_project", __DIR__)
    out_dir = Path.expand("tmp/native_constant_forward_decl_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), native_constant_forward_decl_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_native_wrappers: true
             })

    generated_h = File.read!(Path.join(out_dir, "c/elmc_generated.h"))
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_h =~ "elmc_fn_Main_figureOriginOffsetX("
    refute generated_h =~ "elmc_fn_Main_figureOriginOffsetY("
    refute generated_h =~ "elmc_fn_Main_vectorDrawOrigin("

    native_pos = :binary.match(generated_c, "elmc_fn_Main_vectorDrawOrigin_native")

    offset_x_pos =
      :binary.match(generated_c, "static elmc_int_t elmc_fn_Main_figureOriginOffsetX_native")

    assert native_pos != :nomatch
    assert offset_x_pos != :nomatch
    assert elem(offset_x_pos, 0) < elem(native_pos, 0)
  end

  test "unreachable direct command helpers are not emitted in stripped builds" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/unreachable_direct_command_project", __DIR__)
    out_dir = Path.expand("tmp/unreachable_direct_command_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> unreachable_direct_command_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main"
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_c =~ "elmc_fn_Main_unreachableDirectOps_commands"
  end

  test "direct render only keeps streaming view fallback for small-stack platforms" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_render_only_project", __DIR__)
    out_dir = Path.expand("tmp/direct_render_only_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_native_wrappers: true
             })

    generated_h = File.read!(Path.join(out_dir, "c/elmc_generated.h"))
    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    pebble_c = File.read!(Path.join(out_dir, "c/elmc_pebble.c"))

    assert generated_h =~ "#define ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW 1"
    assert generated_c =~ "elmc_fn_Main_view_commands_append"
    assert generated_h =~ "elmc_fn_Main_init("
    assert generated_h =~ "elmc_fn_Main_update("
    assert generated_h =~ "elmc_fn_Main_subscriptions("
    refute generated_h =~ "elmc_fn_Main_statusDraw("

    assert generated_c =~ ~r/(?:RC|ElmcValue \*) elmc_fn_Main_init\(/
    assert generated_c =~ ~r/(?:RC|ElmcValue \*) elmc_fn_Main_update\(/
    assert generated_c =~ ~r/(?:RC|ElmcValue \*) elmc_fn_Main_subscriptions\(/
    assert generated_c =~ ~r/static (?:RC|int) elmc_fn_Main_view_commands_append\(/

    assert generated_c =~ "elmc_fn_Main_view_scene_append"
    refute generated_c =~ ~r/static (?:RC|ElmcValue \*) elmc_fn_Main_view\(/
    assert generated_c =~ "ELMC_RENDER_OP_PATH_OUTLINE"

    assert pebble_c =~ "#if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)"
    assert pebble_c =~ "#if defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)"
  end

  test "worker drains nested Cmd.batch commands in order" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/cmd_batch_project", __DIR__)
    out_dir = Path.expand("tmp/cmd_batch_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), cmd_batch_main_source())

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "elmc_list_from_values"

    File.write!(Path.join(out_dir, "c/cmd_batch_harness.c"), cmd_batch_harness_source())

    cc = System.find_executable("cc") || System.find_executable("gcc")
    assert is_binary(cc)

    {compile_out, compile_code} =
      System.cmd(
        cc,
        [
          "-std=c11",
          "-Wall",
          "-Wextra",
          "-Iruntime",
          "-Iports",
          "-Ic",
          "runtime/elmc_runtime.c",
          "ports/elmc_ports.c",
          "c/elmc_generated.c",
          "c/elmc_worker.c",
          "c/elmc_pebble.c",
          "c/cmd_batch_harness.c",
          "-lm",
          "-o",
          "cmd_batch_harness"
        ],
        cd: out_dir,
        stderr_to_stdout: true
      )

    assert compile_code == 0, compile_out

    {run_out, run_code} =
      System.cmd(Path.join(out_dir, "cmd_batch_harness"), [], stderr_to_stdout: true)

    assert run_code == 0, run_out
    assert run_out =~ "cmd[0]=8"
    assert run_out =~ "cmd[1]=9"
    assert run_out =~ "cmd[2]=7"
    assert run_out =~ "cmd[3]=0"
  end

  test "runtime extracts specialized UiNode returned from user helpers" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/generic_ui_constructor_project", __DIR__)
    out_dir = Path.expand("tmp/generic_ui_constructor_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), generic_ui_main_source())

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "elmc_fn_Pebble_Ui_toUiNode"
    assert generated_c =~ "ELMC_UI_NODE_WINDOW_STACK"
    assert generated_c =~ "ELMC_UI_NODE_WINDOW"
    assert generated_c =~ "ELMC_UI_NODE_CANVAS_LAYER"
    assert generated_c =~ ~r/elmc_new_int_take\(ELMC_UI_NODE_WINDOW_STACK\)|elmc_new_int\(&tmp_\d+, ELMC_UI_NODE_WINDOW_STACK\)/

    File.write!(Path.join(out_dir, "c/generic_ui_harness.c"), generic_ui_harness_source())

    cc = System.find_executable("cc") || System.find_executable("gcc")
    assert is_binary(cc)

    {compile_out, compile_code} =
      System.cmd(
        cc,
        [
          "-std=c11",
          "-Wall",
          "-Wextra",
          "-Iruntime",
          "-Iports",
          "-Ic",
          "runtime/elmc_runtime.c",
          "ports/elmc_ports.c",
          "c/elmc_generated.c",
          "c/elmc_worker.c",
          "c/elmc_pebble.c",
          "c/generic_ui_harness.c",
          "-lm",
          "-o",
          "generic_ui_harness"
        ],
        cd: out_dir,
        stderr_to_stdout: true
      )

    assert compile_code == 0, compile_out

    {run_out, run_code} =
      System.cmd(Path.join(out_dir, "generic_ui_harness"), [], stderr_to_stdout: true)

    assert run_code == 0, run_out
    assert run_out =~ "view_count=1"
    assert run_out =~ "kind=2 p0=255"
  end

  test "top-level function references compile indexedMap views without zero-arg helper calls" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/top_level_function_reference_project", __DIR__)
    out_dir = Path.expand("tmp/top_level_function_reference_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), top_level_function_reference_source())

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    refute generated_c =~ "elmc_fn_Main_drawCell(NULL, 0)"
    refute generated_c =~ "elmc_closure_new(elmc_fn_Main_drawCell"

    draw_cell_body =
      generated_c
      |> String.split("static RC elmc_fn_Main_drawCell_commands_append_native")
      |> List.last()
      |> String.split("int elmc_fn_", parts: 2)
      |> hd()

    refute draw_cell_body =~ "if (*count >= max_cmds) return 0;"

    File.write!(
      Path.join(out_dir, "c/top_level_function_reference_harness.c"),
      top_level_function_reference_harness_source()
    )

    cc = System.find_executable("cc") || System.find_executable("gcc")
    assert is_binary(cc)

    {compile_out, compile_code} =
      System.cmd(
        cc,
        [
          "-std=c11",
          "-Wall",
          "-Wextra",
          "-Iruntime",
          "-Iports",
          "-Ic",
          "runtime/elmc_runtime.c",
          "ports/elmc_ports.c",
          "c/elmc_generated.c",
          "c/elmc_worker.c",
          "c/elmc_pebble.c",
          "c/top_level_function_reference_harness.c",
          "-lm",
          "-o",
          "top_level_function_reference_harness"
        ],
        cd: out_dir,
        stderr_to_stdout: true
      )

    assert compile_code == 0, compile_out

    {run_out, run_code} =
      System.cmd(Path.join(out_dir, "top_level_function_reference_harness"), [],
        stderr_to_stdout: true
      )

    assert run_code == 0, run_out
    assert run_out =~ "first_count=16"
    assert run_out =~ "view_count=17"
    assert run_out =~ "text[0]=0"
    assert run_out =~ "text[16]=16"
  end

  defp complete_basics_source do
    """
    module Main exposing (basicsBool, basicsFloat, basicsInt, firstClass, main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui


    type alias Model =
        {}


    type Msg
        = NoOp


    basicsFloat : Float
    basicsFloat =
        let
            point =
                fromPolar ( 2, degrees 30 )

            polar =
                toPolar point
        in
        sqrt 9
            + logBase 10 100
            + e
            + pi
            + sin (radians 1)
            + cos (turns 0.25)
            + tan 0.5
            + acos 0.5
            + asin 0.5
            + atan 1
            + atan2 1 1
            + Tuple.first point
            + Tuple.second point
            + Tuple.first polar
            + Tuple.second polar


    firstClass : Float
    firstClass =
        (Basics.sqrt 4)
            + (Basics.logBase 2 8)
            + toFloat (Basics.clamp 0 1 3)
            + (List.sum (List.map Basics.sin [ 0, Basics.pi ]))


    basicsInt : Int
    basicsInt =
        identity
            (round 1.2
                + floor 1.8
                + ceiling 1.2
                + truncate 1.8
                + modBy 5 12
                + remainderBy 5 12
                + clamp 0 10 12
                + max 1 2
                + min 1 2
                + negate 1
                + abs -2
            )


    basicsBool : Bool
    basicsBool =
        not False
            && xor True False
            && (compare basicsInt 0 == GT)
            && always True False
            && isNaN (0 / 0)
            || isInfinite (1 / 0)


    init : Platform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( {}, Cmd.none )


    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )


    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none


    view : Model -> Ui.UiNode
    view _ =
        Ui.windowStack []


    main : Program Decode.Value Model Msg
    main =
        Platform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """
  end

  defp generic_ui_main_source do
    """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi
    import Pebble.Ui.Color as PebbleColor


    type alias Model =
        { value : Int }


    type Msg
        = NoOp


    init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( { value = 0 }, Cmd.none )


    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )


    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none


    view : Model -> PebbleUi.UiNode
    view _ =
        wrapOps [ PebbleUi.clear PebbleColor.white ]


    wrapOps : List PebbleUi.RenderOp -> PebbleUi.UiNode
    wrapOps ops =
        PebbleUi.toUiNode ops


    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """
  end

  defp generic_ui_harness_source do
    """
    #include "elmc_pebble.h"
    #include <stdio.h>

    int main(void) {
      ElmcPebbleApp app = {0};
      ElmcValue *flags = elmc_new_int_take(0);
      int init_rc = elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE);
      elmc_release(flags);
      if (init_rc != 0) return 10;

      ElmcPebbleDrawCmd cmds[4] = {0};
      int count = elmc_pebble_view_commands(&app, cmds, 4);
      printf("view_count=%d\\n", count);
      if (count > 0) {
        printf("kind=%lld p0=%lld\\n", (long long)cmds[0].kind, (long long)cmds[0].p0);
      }
      elmc_pebble_deinit(&app);
      return count == 1 && cmds[0].kind == ELMC_PEBBLE_DRAW_CLEAR && cmds[0].p0 == 255 ? 0 : 20;
    }
    """
  end

  defp top_level_function_reference_source do
    """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { cells : List Int }


    type Msg
        = NoOp


    init : Platform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( { cells = List.range 0 16 }, Cmd.none )


    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )


    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none


    view : Model -> Ui.UiNode
    view model =
        Ui.toUiNode (List.indexedMap drawCell model.cells)


    drawCell : Int -> Int -> Ui.RenderOp
    drawCell index value =
        if index == 16 then
            Ui.textLabel Resources.DefaultFont { x = index * 10, y = 0 } (String.fromInt value)

        else
            Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = index * 10, y = 0, w = 10, h = 10 } (String.fromInt value)


    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """
  end

  defp top_level_function_reference_harness_source do
    """
    #include "elmc_pebble.h"
    #include <stdio.h>
    #include <string.h>

    int main(void) {
      ElmcPebbleApp app = {0};
      ElmcValue *flags = elmc_new_int_take(0);
      int init_rc = elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_APP);
      elmc_release(flags);
      if (init_rc != 0) return 10;

      ElmcPebbleDrawCmd small_cmds[16] = {0};
      int first_count = elmc_pebble_view_commands(&app, small_cmds, 16);
      printf("first_count=%d\\n", first_count);

      ElmcPebbleDrawCmd cmds[32] = {0};
      int count = elmc_pebble_view_commands(&app, cmds, 32);
      printf("view_count=%d\\n", count);
      for (int i = 0; i < count; i++) {
        printf("text[%d]=%s\\n", i, cmds[i].text);
      }

      int ok =
        first_count == 16 &&
        count == 17 &&
        cmds[0].kind == ELMC_PEBBLE_DRAW_TEXT &&
        cmds[16].kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT &&
        strcmp(cmds[0].text, "0") == 0 &&
        strcmp(cmds[16].text, "16") == 0;

      elmc_pebble_deinit(&app);
      return ok ? 0 : 20;
    }
    """
  end

  defp cmd_batch_harness_source do
    """
    #include "elmc_pebble.h"
    #include <stdio.h>

    int main(void) {
      ElmcPebbleApp app = {0};
      ElmcValue *flags = elmc_new_int_take(0);
      int init_rc = elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_WATCHFACE);
      elmc_release(flags);
      if (init_rc != 0) return 10;

      int expected[4] = {
        ELMC_PEBBLE_CMD_GET_CLOCK_STYLE_24H,
        ELMC_PEBBLE_CMD_GET_TIMEZONE_IS_SET,
        ELMC_PEBBLE_CMD_GET_CURRENT_TIME_STRING,
        ELMC_PEBBLE_CMD_NONE
      };

      for (int i = 0; i < 4; i++) {
        ElmcPebbleCmd cmd = {0};
        int rc = elmc_pebble_take_cmd(&app, &cmd);
        if (rc != 0) return 20 + i;
        printf("cmd[%d]=%lld\\n", i, (long long)cmd.kind);
        if (cmd.kind != expected[i]) return 40 + i;
      }

      elmc_pebble_deinit(&app);
      return 0;
    }
    """
  end

  defp cmd_batch_main_source do
    """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Time as PebbleTime
    import Pebble.Ui as PebbleUi
    import Pebble.Ui.Color as PebbleColor


    type alias Model =
        { value : Int }


    type Msg
        = CurrentTimeString String
        | ClockStyle24h Bool
        | TimezoneIsSet Bool


    requestSystemInfo : Cmd Msg
    requestSystemInfo =
        Cmd.batch
            [ PebbleTime.clockStyle24h ClockStyle24h
            , PebbleTime.timezoneIsSet TimezoneIsSet
            ]


    init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( { value = 0 }
        , Cmd.batch
            [ requestSystemInfo
            , PebbleTime.currentTimeString CurrentTimeString
            ]
        )


    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )


    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none


    view : Model -> PebbleUi.UiNode
    view _ =
        PebbleUi.windowStack
            [ PebbleUi.window 1
                [ PebbleUi.canvasLayer 1
                    [ PebbleUi.clear PebbleColor.black ]
                ]
            ]


    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """
  end

  defp operator_section_cons_source do
    """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui


    type alias Model =
        { cells : List Int }


    type Msg
        = Move


    init : Platform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( { cells = [ 2, 2, 0, 0 ] }, Cmd.none )


    update : Msg -> Model -> ( Model, Cmd Msg )
    update msg model =
        case msg of
            Move ->
                let
                    next =
                        merge (List.filter ((/=) 0) model.cells)
                in
                if next == model.cells then
                    ( model, Cmd.none )

                else
                    ( { model | cells = 1 :: next }, Cmd.none )


    merge : List Int -> List Int
    merge values =
        case values of
            a :: b :: rest ->
                if a == b then
                    a + b :: merge rest

                else
                    a :: merge (b :: rest)

            _ ->
                values


    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none


    view : Model -> Ui.UiNode
    view _ =
        Ui.windowStack
            [ Ui.window 1
                [ Ui.canvasLayer 1 [] ]
            ]


    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """
  end

  defp minimal_harness_source do
    """
    #include "elmc_pebble.h"

    int main(void) {
      ElmcPebbleApp app = {0};
      ElmcValue *flags = elmc_new_int_take(0);
      int rc = elmc_pebble_init_with_mode(&app, flags, ELMC_PEBBLE_MODE_APP);
      elmc_release(flags);
      elmc_pebble_deinit(&app);
      return rc == 0 ? 0 : 1;
    }
    """
  end

  defp typed_int_arg_source do
    """


    typedBounds : Int -> Int -> { x : Int, y : Int, w : Int, h : Int }
    typedBounds x y =
        { x = x, y = y, w = 10, h = 12 }


    typedBoundsAccess : Int -> Int -> Int
    typedBoundsAccess x y =
        let
            bounds =
                { x = x, y = y, w = 10, h = 12 }
        in
        bounds.x
    """
  end

  defp trig_round_native_source do
    """


    trigRoundScore : Int -> Int
    trigRoundScore degrees =
        Basics.round (Basics.sin degrees * Basics.toFloat 100)
    """
  end

  defp native_int_case_source do
    """


    nativeIntCase : Int -> Int
    nativeIntCase sector =
        case modBy 8 sector of
            0 ->
                1

            1 ->
                2

            2 ->
                3

            _ ->
                4
    """
  end

  defp native_int_case_string_source do
    """


    nativeIntCaseString : Int -> String
    nativeIntCaseString month =
        case month of
            1 ->
                "Jan"

            2 ->
                "Feb"

            3 ->
                "Mar"

            _ ->
                ""
    """
  end

  defp boxed_constructor_case_string_source do
    """


    type BoxedDirection
        = BoxedNorth
        | BoxedSouth
        | BoxedEast
        | BoxedWest


    boxedDirectionString : BoxedDirection -> String
    boxedDirectionString direction =
        case direction of
            BoxedNorth ->
                "N"

            BoxedSouth ->
                "S"

            BoxedEast ->
                "E"

            BoxedWest ->
                "W"
    """
  end

  defp native_bool_field_source do
    """


    type alias NativeBoolFieldModel =
        { isRound : Bool }


    nativeBoolField : NativeBoolFieldModel -> Int
    nativeBoolField model =
        if model.isRound then
            1

        else
            2


    nativeBoolHelper : NativeBoolFieldModel -> Bool
    nativeBoolHelper model =
        model.isRound


    nativeBoolHelperColor : NativeBoolFieldModel -> Int
    nativeBoolHelperColor model =
        let
            color =
                if nativeBoolHelper model then
                    192

                else
                    255
        in
        color


    nativeBoolMixedBranches : Maybe Int -> Int -> Bool
    nativeBoolMixedBranches maybeValue value =
        if value < 0 then
            True

        else
            maybeValue == Just 25


    nativeBoolMaybeBranchReuse : Bool -> Maybe Int -> Maybe Int
    nativeBoolMaybeBranchReuse flag maybeValue =
        if flag then
            maybeValue

        else
            Just 25
    """
  end

  defp boxed_int_equality_source do
    """


    replaceAt : Int -> Int -> List Int -> List Int
    replaceAt index newValue cells =
        List.indexedMap
            (\\i value ->
                if i == index then
                    newValue

                else
                    value
            )
            cells
    """
  end

  defp integer_let_arithmetic_source do
    """


    integerLetArithmetic : Int -> Int -> Int
    integerLetArithmetic width height =
        let
            headerBottom =
                if height <= 144 then
                    32

                else
                    36

            target =
                2 * (height - headerBottom) - width
        in
        target
    """
  end

  defp native_min_record_fields_source do
    """


    type alias NativeMinRecordModel =
        { screenW : Int
        , screenH : Int
        }


    nativeMinRecordFields : NativeMinRecordModel -> Int
    nativeMinRecordFields model =
        min model.screenW model.screenH
    """
  end

  defp record_field_order_source do
    """


    type alias WatchModel =
        { now : Maybe Int
        , screenW : Int
        , screenH : Int
        , colorMode : Int
        , companionFigure : Maybe Int
        , downloadedPieces : List Int
        , pendingFigure : Maybe Int
        }


    watchModelArea : WatchModel -> Int
    watchModelArea model =
        model.screenW + model.screenH


    probeWatchModelArea : Int
    probeWatchModelArea =
        watchModelArea
            { now = Nothing
            , screenW = 1
            , screenH = 2
            , colorMode = 0
            , companionFigure = Nothing
            , downloadedPieces = []
            , pendingFigure = Nothing
            }
    """
  end

  defp native_string_from_int_source do
    """


    nativeStringFromInt : Int -> String
    nativeStringFromInt value =
        String.fromInt (value + 1)


    nativeStringAppend : Int -> String
    nativeStringAppend value =
        String.append "0" (String.fromInt value)
    """
  end

  defp boxed_string_if_source do
    """


    boxedStringIf : Int -> String
    boxedStringIf value =
        let
            prefix =
                if value < 0 then
                    "-"

                else
                    ""
        in
        String.append prefix (String.fromInt value)
    """
  end

  defp native_maybe_default_string_source do
    """


    type alias NativeMaybeDefaultStringModel =
        { batteryLevel : Maybe Int }


    nativeStringSink : String -> String
    nativeStringSink value =
        value


    nativeMaybeDefaultString : NativeMaybeDefaultStringModel -> String
    nativeMaybeDefaultString model =
        String.fromInt (Maybe.withDefault 0 model.batteryLevel)


    nativeMaybeDefaultStringArg : NativeMaybeDefaultStringModel -> String
    nativeMaybeDefaultStringArg model =
        nativeStringSink (String.fromInt (Maybe.withDefault 0 model.batteryLevel))


    nativeMaybeDefaultHeadString : List Int -> String
    nativeMaybeDefaultHeadString values =
        String.fromInt (Maybe.withDefault 0 (List.head values))


    nativeMaybeDefaultDictString : Int -> Dict.Dict Int Int -> String
    nativeMaybeDefaultDictString key values =
        String.fromInt (Maybe.withDefault 0 (Dict.get key values))
    """
  end

  defp native_bool_arg_source do
    """


    nativeBoolBranch : Bool -> Int -> String
    nativeBoolBranch enabled value =
        if enabled then
            String.fromInt value

        else
            "off"


    nativeBoolCall : Bool -> String
    nativeBoolCall enabled =
        nativeBoolBranch enabled 7


    nativeBoolCaptured : Bool -> Int -> Int
    nativeBoolCaptured enabled value =
        let
            test _ =
                enabled
        in
        if test value then
            value

        else
            0


    nativeBoolBoxedUse : Bool -> Int -> Int
    nativeBoolBoxedUse enabled value =
        if List.member enabled [ True ] then
            value

        else
            0


    nativeBoolCompareBranch : Bool -> Bool -> String
    nativeBoolCompareBranch left right =
        if left == right then
            "same"

        else
            "diff"


    nativeBoolCompareCall : Bool -> Bool -> String
    nativeBoolCompareCall left right =
        nativeBoolBranch (left /= right) 3
    """
  end

  defp native_literal_division_source do
    """


    nativeLiteralDivision : Int -> String
    nativeLiteralDivision value =
        String.fromInt (value * 328 // 100)
    """
  end

  defp native_helper_arg_let_source do
    """


    nativeIntSink : Int -> Int -> Int
    nativeIntSink y radius =
        y + radius


    nativeHelperArgLet : Int -> Int -> Int
    nativeHelperArgLet cy radius =
        let
            moonPhaseY =
                cy + (radius // 2)
        in
        nativeIntSink moonPhaseY (max 10 (radius // 5))


    opaqueStringLength : String -> Int
    opaqueStringLength label =
        String.length label


    typedIntReturnReuse : String -> Int
    typedIntReturnReuse label =
        let
            minutes =
                opaqueStringLength label

            hours =
                minutes // 60
        in
        nativeIntSink hours (modBy 60 minutes)
    """
  end

  defp enum_compare_source do
    """


    type EnumUnit
        = MetersPerSecond
        | MilesPerHour


    enumUnitString : EnumUnit -> String
    enumUnitString unit =
        if unit == MilesPerHour then
            "mph"

        else
            "m/s"
    """
  end

  defp native_abs_negate_source do
    """


    nativeAbsNegate : Int -> Int
    nativeAbsNegate phaseE6 =
        abs (phaseE6 - 500000) + negate phaseE6
    """
  end

  defp helper_record_field_source do
    """


    helperRecordFieldBounds : Int -> Int -> { x : Int, y : Int, w : Int, h : Int }
    helperRecordFieldBounds x y =
        { x = x + 1, y = y + 2, w = 10, h = 12 }


    helperRecordFieldOps : Int -> Int -> List PebbleUi.RenderOp
    helperRecordFieldOps x y =
        [ PebbleUi.arc (helperRecordFieldBounds x y) 0 1 ]
    """
  end

  defp native_text_arg_source do
    """


    nativeTextAt : Pebble.Ui.Color.Color -> String -> List PebbleUi.RenderOp
    nativeTextAt color value =
        PebbleUi.group
            (PebbleUi.context
                [ PebbleUi.textColor color ]
                [ PebbleUi.text UiResources.DefaultFont PebbleUi.defaultTextOptions { x = 1, y = 2, w = 30, h = 12 } value ]
            )


    nativeTextAtAlias : PebbleColor.Color -> String -> List PebbleUi.RenderOp
    nativeTextAtAlias color value =
        PebbleUi.group
            (PebbleUi.context
                [ PebbleUi.textColor color ]
                [ PebbleUi.text UiResources.DefaultFont PebbleUi.defaultTextOptions { x = 1, y = 2, w = 30, h = 12 } value ]
            )


    nativeTextAtExplicitAlias : Color.Color -> String -> List PebbleUi.RenderOp
    nativeTextAtExplicitAlias color value =
        PebbleUi.group
            (PebbleUi.context
                [ PebbleUi.textColor color ]
                [ PebbleUi.text UiResources.DefaultFont PebbleUi.defaultTextOptions { x = 1, y = 2, w = 30, h = 12 } value ]
            )


    nativeTextAtExposedType : Color -> String -> List PebbleUi.RenderOp
    nativeTextAtExposedType color value =
        PebbleUi.group
            (PebbleUi.context
                [ PebbleUi.textColor color ]
                [ PebbleUi.text UiResources.DefaultFont PebbleUi.defaultTextOptions { x = 1, y = 2, w = 30, h = 12 } value ]
            )


    nativeTextLiteral : List PebbleUi.RenderOp
    nativeTextLiteral =
        nativeTextAt PebbleColor.white "Direct"


    nativeTextLet : Int -> List PebbleUi.RenderOp
    nativeTextLet value =
        let
            label =
                if value == 0 then
                    "Zero"

                else
                    String.fromInt value
        in
        nativeTextAt PebbleColor.white label


    nativeTextAliasIf : Bool -> List PebbleUi.RenderOp
    nativeTextAliasIf enabled =
        let
            color =
                if enabled then
                    PebbleColor.black

                else
                    PebbleColor.white
        in
        nativeTextAtAlias color "Alias"


    nativeTextExplicitAliasIf : Bool -> List PebbleUi.RenderOp
    nativeTextExplicitAliasIf enabled =
        let
            color =
                if enabled then
                    Color.black

                else
                    Color.white
        in
        nativeTextAtExplicitAlias color "Explicit"


    nativeTextExposedTypeIf : Bool -> List PebbleUi.RenderOp
    nativeTextExposedTypeIf enabled =
        let
            color =
                if enabled then
                    Color.black

                else
                    Color.white
        in
        nativeTextAtExposedType color "Exposed"


    nativeTextBounds : PebbleUi.Rect -> String -> List PebbleUi.RenderOp
    nativeTextBounds bounds value =
        PebbleUi.text UiResources.DefaultFont PebbleUi.defaultTextOptions bounds value


    nativeTextHelper : Int -> String
    nativeTextHelper value =
        String.fromInt value


    nativeTextFromHelper : Int -> List PebbleUi.RenderOp
    nativeTextFromHelper value =
        PebbleUi.text UiResources.DefaultFont PebbleUi.defaultTextOptions { x = 1, y = 2, w = 30, h = 12 } (nativeTextHelper value)
    """
  end

  defp text_options_source do
    """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Resources as Resources


    type alias Model =
        {}


    type Msg
        = NoOp


    init : Platform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( {}, Cmd.none )


    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )


    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none


    view : Model -> Ui.UiNode
    view _ =
        Ui.toUiNode
            [ Ui.text Resources.DefaultFont (Ui.alignLeft Ui.defaultTextOptions) { x = 0, y = 0, w = 30, h = 12 } "Left"
            , Ui.text Resources.DefaultFont (Ui.trailingEllipsis Ui.defaultTextOptions) { x = 0, y = 12, w = 30, h = 12 } "Center"
            , Ui.text Resources.DefaultFont (Ui.fillOverflow (Ui.alignRight Ui.defaultTextOptions)) { x = 0, y = 24, w = 30, h = 12 } "Right"
            ]


    main : Program Decode.Value Model Msg
    main =
        Platform.application
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """
  end

  defp direct_native_let_circle_radius_source do
    """


    directNativeLetCircleRadius : Int -> Int -> List PebbleUi.RenderOp
    directNativeLetCircleRadius screenW screenH =
        let
            centerX =
                screenW // 2

            centerY =
                screenH // 2

            radius =
                max 22 ((min screenW screenH // 2) - 14)
        in
        [ PebbleUi.circle { x = centerX, y = centerY } radius PebbleColor.black ]
    """
  end

  defp native_unit12_lookup_source do
    """


    unit12X : Int -> Int
    unit12X index =
        case modBy 12 index of
            0 -> 0
            1 -> 500
            3 -> 1000
            _ -> -500

    unit12Y : Int -> Int
    unit12Y index =
        case modBy 12 index of
            0 -> -1000
            3 -> 0
            _ -> -500
    """
  end

  defp direct_native_let_analog_markers_source do
    """


    unit12X : Int -> Int
    unit12X index =
        case modBy 12 index of
            0 -> 0
            3 -> 1000
            _ -> 500

    unit12Y : Int -> Int
    unit12Y index =
        case modBy 12 index of
            0 -> -1000
            3 -> 0
            _ -> -500

    handX : Int -> Int -> Int -> Int
    handX centerX handRadius index =
        centerX + ((unit12X index * handRadius) // 1000)

    handY : Int -> Int -> Int -> Int
    handY centerY handRadius index =
        centerY + ((unit12Y index * handRadius) // 1000)

    directNativeLetAnalogMarkers : Int -> Int -> List PebbleUi.RenderOp
    directNativeLetAnalogMarkers screenW screenH =
        let
            centerX =
                screenW // 2

            centerY =
                screenH // 2

            radius =
                max 22 ((min screenW screenH // 2) - 14)

            markerTopX =
                handX centerX radius 0

            markerTopY =
                handY centerY radius 0
        in
        [ PebbleUi.pixel { x = markerTopX, y = markerTopY } PebbleColor.black ]
    """
  end

  defp direct_unit12_dedup_source do
    direct_native_let_analog_markers_source() <>
      """


      directUnit12Dedup : Int -> Int -> Int -> Int -> List PebbleUi.RenderOp
      directUnit12Dedup screenW screenH minute hour =
          let
              centerX =
                  screenW // 2

              centerY =
                  screenH // 2

              radius =
                  max 22 ((min screenW screenH // 2) - 14)

              minuteIndex =
                  modBy 12 (minute // 5)

              hourIndex =
                  modBy 12 (hour + (minute // 30))

              minuteX =
                  handX centerX radius minuteIndex

              minuteY =
                  handY centerY radius minuteIndex

              hourX =
                  handX centerX radius hourIndex

              markerTopX =
                  handX centerX radius 0

              markerTopY =
                  handY centerY radius 0
          in
          [ PebbleUi.pixel { x = markerTopX, y = markerTopY } PebbleColor.black
          , PebbleUi.line { x = centerX, y = centerY } { x = minuteX, y = minuteY } PebbleColor.black
          , PebbleUi.line { x = centerX, y = centerY } { x = hourX, y = centerY } PebbleColor.black
          ]
      """
  end

  defp direct_native_let_bounds_source do
    """


    directNativeLetBounds : Int -> Int -> List PebbleUi.RenderOp
    directNativeLetBounds screenW screenH =
        let
            x =
                screenW - 64

            y =
                screenH - 36
        in
        [ PebbleUi.text UiResources.DefaultFont PebbleUi.defaultTextOptions { x = x, y = y, w = 60, h = 18 } "Alt" ]
    """
  end

  defp calendar_label_helper_source do
    """


    calendarLabelView : Int -> String -> String -> PebbleUi.UiNode
    calendarLabelView screenW timeString eventLine =
        let
            lineH =
                18

            startY =
                36

            label x y text_ =
                PebbleUi.text UiResources.DefaultFont PebbleUi.defaultTextOptions { x = x, y = y, w = screenW - 16, h = lineH } text_

        in
        PebbleUi.windowStack
            [ PebbleUi.window 1
                [ PebbleUi.canvasLayer 1
                    [ PebbleUi.clear PebbleColor.white
                    , label 8 startY timeString
                    , label 8 (startY + lineH) "Next event"
                    , label 8 (startY + lineH * 2) eventLine
                    ]
                ]
            ]
    """
  end

  defp self_referential_substitution_source do
    """


    selfReferentialBounds : Int -> { x : Int, y : Int, w : Int, h : Int }
    selfReferentialBounds x =
        { x = x - 1, y = 0, w = 10, h = 10 }


    selfReferentialOps : Int -> List PebbleUi.RenderOp
    selfReferentialOps x =
        [ PebbleUi.rect (selfReferentialBounds (x - 1)) PebbleColor.black ]
    """
  end

  defp direct_native_if_let_source do
    """


    directNativeIfLet : Int -> Int -> Int -> List PebbleUi.RenderOp
    directNativeIfLet cx radius phaseE6 =
        let
            lit =
                (abs (phaseE6 - 500000) * radius) // 500000

            offset =
                if phaseE6 < 500000 then
                    negate lit

                else
                    lit
        in
        [ PebbleUi.fillCircle { x = cx + offset, y = 0 } radius PebbleColor.black ]
    """
  end

  defp direct_native_bool_condition_source do
    """


    directNativeBoolCondition : Bool -> List PebbleUi.RenderOp
    directNativeBoolCondition enabled =
        if enabled then
            [ PebbleUi.clear PebbleColor.black ]

        else
            [ PebbleUi.clear PebbleColor.white ]


    directEmptyThenCondition : Bool -> List PebbleUi.RenderOp
    directEmptyThenCondition enabled =
        if enabled then
            []

        else
            [ PebbleUi.clear PebbleColor.white ]


    opaqueStringLength : String -> Int
    opaqueStringLength label =
        String.length label


    directTypedIntResultReuse : Bool -> String -> List PebbleUi.RenderOp
    directTypedIntResultReuse enabled label =
        let
            minutes =
                opaqueStringLength label
        in
        if enabled then
            [ PebbleUi.textInt UiResources.DefaultFont { x = 0, y = 0, w = 30, h = 12 } minutes ]

        else
            [ PebbleUi.clear PebbleColor.white ]
    """
  end

  defp wildcard_case_condition_source do
    """


    wildcardCaseCondition : Maybe Int -> Int
    wildcardCaseCondition maybeValue =
        case maybeValue of
            Just value ->
                value

            _ ->
                0


    wildcardCaseConditionOps : Maybe Int -> List PebbleUi.RenderOp
    wildcardCaseConditionOps maybeValue =
        case maybeValue of
            Just _ ->
                [ PebbleUi.clear PebbleColor.black ]

            _ ->
                [ PebbleUi.clear PebbleColor.white ]
    """
  end

  defp direct_maybe_default_helper_arg_source do
    """


    type alias DirectMaybeDefaultModel =
        { moonsetMin : Maybe Int }


    type alias DirectSunModel =
        { sun : Maybe DirectSunWindow }


    type alias DirectSunWindow =
        { sunriseMin : Int
        , sunsetMin : Int
        }


    defaultDirectSunWindow : DirectSunWindow
    defaultDirectSunWindow =
        { sunriseMin = 360
        , sunsetMin = 1080
        }


    helperAngle : Int -> Int
    helperAngle value =
        value + 1


    directMaybeDefaultHelperArg : DirectMaybeDefaultModel -> List PebbleUi.RenderOp
    directMaybeDefaultHelperArg model =
        let
            moonset =
                Maybe.withDefault 720 model.moonsetMin

            x =
                helperAngle moonset
        in
        [ PebbleUi.line { x = 0, y = 0 } { x = x, y = 0 } PebbleColor.white ]


    directSunWindowFields : DirectSunModel -> List PebbleUi.RenderOp
    directSunWindowFields model =
        let
            sunWindow =
                Maybe.withDefault defaultDirectSunWindow model.sun

            sunrise =
                sunWindow.sunriseMin

            sunset =
                sunWindow.sunsetMin
        in
        [ PebbleUi.line { x = sunrise, y = 0 } { x = sunset, y = 0 } PebbleColor.white ]
    """
  end

  defp native_lambda_arg_source do
    """


    nativeLambdaArgStrings : List Int -> List String
    nativeLambdaArgStrings hours =
        List.map
            (\\nativeHourForLambda ->
                if modBy 2 nativeHourForLambda == 0 then
                    String.fromInt nativeHourForLambda

                else
                    String.fromInt (nativeHourForLambda + 1)
            )
            hours
    """
  end

  defp native_boxed_record_compare_source do
    """


    type alias NativeBoxedRecordCompareModel =
        { sunriseMin : Int }


    nativeBoxedRecordCompare : NativeBoxedRecordCompareModel -> Int
    nativeBoxedRecordCompare model =
        let
            sunrise =
                model.sunriseMin
        in
        if sunrise < 720 then
            1

        else if sunrise == 720 then
            2

        else
            3
    """
  end

  defp native_constant_forward_decl_source do
    """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi
    import Pebble.Ui.Color as PebbleColor
    import Pebble.Ui.Resources as UiResources


    type alias Model =
        { scale : Int }


    type Msg
        = NoOp


    init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( { scale = 100 }, Cmd.none )


    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )


    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none


    scaled : Int -> Int -> Int
    scaled scale value =
        (value * scale) // 100


    figureOriginOffsetX : Int
    figureOriginOffsetX =
        66


    figureOriginOffsetY : Int
    figureOriginOffsetY =
        58


    vectorDrawOrigin : Int -> Int
    vectorDrawOrigin scale =
        scaled scale figureOriginOffsetX + scaled scale figureOriginOffsetY


    view : Model -> PebbleUi.UiNode
    view model =
        PebbleUi.windowStack
            [ PebbleUi.window 1
                [ PebbleUi.canvasLayer 1
                    [ PebbleUi.textInt UiResources.DefaultFont { x = 0, y = 0 } (vectorDrawOrigin model.scale) ]
                ]
            ]


    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """
  end

  defp native_only_wrapper_source do
    """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as PebblePlatform
    import Pebble.Ui as PebbleUi
    import Pebble.Ui.Color as PebbleColor
    import Pebble.Ui.Resources as UiResources


    type alias Model =
        {}


    type Msg
        = NoOp


    init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
    init _ =
        ( {}, Cmd.none )


    update : Msg -> Model -> ( Model, Cmd Msg )
    update _ model =
        ( model, Cmd.none )


    subscriptions : Model -> Sub Msg
    subscriptions _ =
        Sub.none


    nativeOnlyHelper : Int -> Int
    nativeOnlyHelper value =
        value + 1


    view : Model -> PebbleUi.UiNode
    view _ =
        PebbleUi.windowStack
            [ PebbleUi.window 1
                [ PebbleUi.canvasLayer 1
                    [ PebbleUi.textInt UiResources.DefaultFont { x = 0, y = 0 } (nativeOnlyHelper 7) ]
                ]
            ]


    main : Program Decode.Value Model Msg
    main =
        PebblePlatform.watchface
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """
  end

  test "maybe record fields in tuple case patterns use boxed tuple access" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/maybe_tuple_case_project", __DIR__)
    out_dir = Path.expand("tmp/maybe_tuple_case_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), maybe_tuple_case_source())

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    weather_string_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_weatherString")

    refute weather_string_body =~ "elmc_tuple2_ints(ELMC_RECORD_GET_INDEX_INT"
    assert weather_string_body =~ "elmc_record_get_index"
  end

  defp maybe_tuple_case_source do
    """
    module Main exposing (main)

    import Json.Decode as Decode
    import Pebble.Platform as Platform
    import Pebble.Ui as Ui


    type alias Model =
        { temperature : Maybe Int
        , condition : Maybe Int
        }


    type Msg
        = Tick


    init _ =
        ( { temperature = Nothing, condition = Nothing }, Cmd.none )


    update msg model =
        case msg of
            Tick ->
                ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    weatherString : Model -> String
    weatherString model =
        case ( model.temperature, model.condition ) of
            ( Just _, Just _ ) ->
                "Ready"

            _ ->
                "Loading..."


    view model =
        Ui.root [ Ui.text 0 { x = 0, y = 0 } (weatherString model) ]


    main =
        Platform.watchProgram
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }
    """
  end

  defp unreachable_direct_command_source do
    """


    unreachableDirectOps : List PebbleUi.RenderOp
    unreachableDirectOps =
        [ PebbleUi.clear PebbleColor.black
        , PebbleUi.line { x = 0, y = 0 } { x = 10, y = 10 } PebbleColor.white
        ]
    """
  end

  test "animated vector draw ops use pebble vector resource slot 2 when static is slot 1" do
    source_template =
      Path.expand("../../ide/priv/project_templates/watch_demo_drawing_showcase", __DIR__)

    project_dir = Path.expand("tmp/vector_resource_slot_project", __DIR__)
    out_dir = Path.expand("tmp/vector_resource_slot_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_template, project_dir)

    File.write!(
      Path.join(project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => [
          "src",
          "../../../../packages/elm-pebble/elm-watch/src"
        ],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    animated_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_animatedVectorOps")
      |> CCodegenExtract.before_next_fn()

    assert animated_body =~ "ELMC_RENDER_OP_VECTOR_SEQUENCE_AT"
    refute animated_body =~ "elmc_fn_Pebble_Ui_Resources_VectorAnimated"
    refute animated_body =~ "VectorStaticWeatherClear"

    static_body =
      CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_staticVectorOps")
      |> CCodegenExtract.before_next_fn()

    assert static_body =~ "ELMC_RENDER_OP_VECTOR_AT"
    refute static_body =~ "elmc_fn_Pebble_Ui_Resources_VectorStatic"
    refute static_body =~ "VectorAnimatedTransitionClearToCloudy"
  end

  test "rotationFromDegrees literal folds to Rotation union for path rotation args" do
    source_template =
      Path.expand("../../ide/priv/project_templates/watch_demo_drawing_showcase", __DIR__)

    project_dir = Path.expand("tmp/drawing_rotation_union_project", __DIR__)
    out_dir = Path.expand("tmp/drawing_rotation_union_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(source_template, project_dir)

    File.write!(
      Path.join(project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => [
          "src",
          "../../../../packages/elm-pebble/elm-watch/src"
        ],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    paths_direct_body =
      generated_c
      |> String.split(
        "static RC elmc_fn_Main_pathsOps_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {"
      )
      |> Enum.at(1)
      |> String.split(
        "RC elmc_fn_Main_pathsOps_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {"
      )
      |> hd()

    assert paths_direct_body =~ "scene_cmd.path_rotation = 0"
    refute paths_direct_body =~ "elmc_fn_Pebble_Ui_rotationFromDegrees"
    refute paths_direct_body =~ "elmc_fn_Pebble_Ui_rotationToPebbleAngle"

    bitmap_body =
      generated_c
      |> String.split(
        "static RC elmc_fn_Main_staticBitmapOps_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {"
      )
      |> Enum.at(1)
      |> String.split(
        "RC elmc_fn_Main_staticBitmapOps_scene_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer) {"
      )
      |> hd()

    assert bitmap_body =~
             "scene_cmd.p3 = ELMC_RECORD_GET_INDEX_INT(model, ELMC_FIELD_MAIN_MODEL_ROTATIONANGLE)"
    refute bitmap_body =~ "elmc_fn_Pebble_Ui_rotationToPebbleAngle"
  end

  test "direct List.map over List.range uses native append without boxing loop items" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_map_range_native_project", __DIR__)
    out_dir = Path.expand("tmp/direct_map_range_native_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_map_range_native_source())

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_item_i_"
    assert view_body =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "elmc_new_int(direct_item_i_"
    refute view_body =~ "ELMC_TAG_LIST"
    refute view_body =~ "_commands_append(direct_call_args_"
  end

  test "direct textAt with defaultTextOptions is supported in view" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_textat_default_project", __DIR__)
    out_dir = Path.expand("tmp/direct_textat_default_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_textat_default_options_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })
  end

  test "direct view composes helpers that call other direct command targets" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_helper_chain_project", __DIR__)
    out_dir = Path.expand("tmp/direct_helper_chain_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_helper_chain_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "view_commands_append"
    refute generated_c =~ "ELMC_TAG_LIST"
    # Single-call chain: view -> chrome -> dial (no separate chrome/dial defs).
    refute generated_c =~ "elmc_fn_Main_chrome_commands_append"
    refute generated_c =~ "elmc_fn_Main_dial_commands_append"
  end

  test "direct List.concatMap over range inlines watchface-style hour ticks" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_concatmap_ticks_project", __DIR__)
    out_dir = Path.expand("tmp/direct_concatmap_ticks_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_concatmap_range_ticks_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "view_commands_append"
    refute generated_c =~ "ELMC_TAG_LIST"
  end

  test "direct List.concatMap over range inlines tick lines from lambda" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_concatmap_range_project", __DIR__)
    out_dir = Path.expand("tmp/direct_concatmap_range_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_concatmap_range_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_item_i_"
    assert view_body =~ "ELMC_RENDER_OP_LINE"
    refute view_body =~ "ELMC_TAG_LIST"
  end

  test "direct List.map over range inlines affine textInt draw commands" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_map_affine_project", __DIR__)
    out_dir = Path.expand("tmp/direct_map_affine_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_map_affine_source())

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_item_i_"
    assert view_body =~ "elmc_scene_writer_push_cmd"
    assert view_body =~ "direct_item_i_"
    refute view_body =~ "elmc_fn_Main_row_commands_append_native"
  end

  test "direct List.indexedMap over range inlines affine textInt draw commands" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_indexed_affine_project", __DIR__)
    out_dir = Path.expand("tmp/direct_indexed_affine_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_indexed_map_affine_source())

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_index_"
    assert view_body =~ "direct_item_i_"
    assert view_body =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "elmc_fn_Main_row_commands_append_native"
    refute view_body =~ "elmc_new_int(direct_index_"
  end

  test "direct List.indexedMap over model field list inlines affine drawCell body" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_indexed_affine_cells_project", __DIR__)
    out_dir = Path.expand("tmp/direct_indexed_affine_cells_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_indexed_map_affine_cells_source())

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_index_"
    assert view_body =~ "ELMC_RENDER_OP_PUSH_CONTEXT"
    assert view_body =~ "ELMC_RENDER_OP_RECT"
    refute view_body =~ "elmc_fn_Main_drawCell_commands_append_native"
    refute generated_c =~ "elmc_fn_Main_drawCell_commands_append"

    assert view_body |> String.split("ELMC_RENDER_OP_PUSH_CONTEXT") |> length() == 2
    assert view_body |> String.split("ELMC_RENDER_OP_POP_CONTEXT") |> length() == 2
  end

  test "direct List.indexedMap over model field list inlines affine text from int label" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_indexed_affine_cells_text_project", __DIR__)
    out_dir = Path.expand("tmp/direct_indexed_affine_cells_text_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      direct_indexed_map_affine_cells_text_source()
    )

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "ELMC_RENDER_OP_TEXT"
    assert view_body =~ "elmc_scene_text_from_nonzero_int"
    assert view_body =~ "scene_cmd.text[0] = '.';"
    refute view_body =~ "snprintf(scene_cmd.text"
    refute view_body =~ "const char *direct_text = \".\";"
    refute view_body =~ "elmc_fn_Main_drawCell_commands_append_native"
  end

  test "direct indexedMap drawCell skips fillRect when cell value is zero" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_indexed_affine_cells_fill_skip_project", __DIR__)
    out_dir = Path.expand("tmp/direct_indexed_affine_cells_fill_skip_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      direct_indexed_map_affine_cells_fill_skip_source()
    )

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "ELMC_RENDER_OP_RECT"
    assert view_body =~ "ELMC_RENDER_OP_FILL_RECT"
    assert view_body =~ "if (elmc_as_int(direct_node_"
    assert view_body =~ "ELMC_RENDER_OP_FILL_RECT"
    assert view_body =~ "!= 0)"
    refute view_body =~ "elmc_fn_Main_drawCell_commands_append_native"
  end

  test "direct view List.cons and append compose chrome with inlined indexedMap cells" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_view_cons_project", __DIR__)
    out_dir = Path.expand("tmp/direct_view_cons_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_view_cons_cells_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_index_"
    assert view_body =~ "ELMC_RENDER_OP_CLEAR"
    refute view_body =~ "elmc_fn_Main_drawCell_commands_append_native"
  end

  test "direct List.indexedMap with layout prefix inlines grid affine drawCell body" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_indexed_affine_layout_project", __DIR__)
    out_dir = Path.expand("tmp/direct_indexed_affine_layout_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    File.write!(
      Path.join(project_dir, "src/Main.elm"),
      direct_indexed_map_affine_layout_cells_source()
    )

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_index_"
    assert view_body =~ "direct_native_record_layout_cell_"
    assert view_body =~ "% 4"
    assert view_body =~ "/ 4)"
    assert view_body =~ "ELMC_RENDER_OP_RECT"
    refute view_body =~ "elmc_fn_Main_drawCell_commands_append_native"
    refute generated_c =~ "elmc_fn_Main_boardLayout("
    assert view_body =~ "direct_native_record_layout_x_"
    assert view_body =~ "direct_native_record_layout_cell_"
    refute view_body =~ "elmc_record_new_ints"
    refute view_body =~ "ELMC_RECORD_GET_INDEX_INT(,"
    assert view_body =~ "direct_native_record_layout_cell_"
    assert view_body =~ "ELMC_RENDER_OP_TEXT"
    assert view_body =~ "direct_stride_"
    assert view_body =~ "direct_cell_x_"
    assert view_body =~ "direct_cell_y_"
    assert view_body =~ "direct_text_y_"
    assert view_body =~ "scene_cmd.p0 = direct_cell_x_"
    assert view_body =~ "scene_cmd.p1 = direct_cell_y_"
    assert view_body =~ "scene_cmd.p2 = direct_text_y_"
    refute view_body =~ "scene_cmd.p1 = (ELMC_TEXT_ALIGN_CENTER"

    cell_loop =
      view_body
      |> String.split(~r/while \(Rc == RC_SUCCESS && direct_cursor_/, parts: 2)
      |> Enum.at(1, "")
      |> String.split("elmc_release", parts: 2)
      |> hd()

    assert length(String.split(cell_loop, "elmc_scene_writer_push_cmd")) >= 2,
           "expected per-command scene writer pushes in affine indexedMap loop"
  end

  test "direct view reuses hoisted displayShapeIsRound across layout and chrome lets" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_display_shape_hoist_project", __DIR__)
    out_dir = Path.expand("tmp/direct_display_shape_hoist_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_display_shape_hoist_view_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    refute view_body =~ "elmc_fn_Pebble_Platform_displayShapeIsRound"
    assert view_body =~ "#if defined(PBL_ROUND)"
    refute view_body =~ "native_union_subject_"
    refute view_body =~ "if (native_b_"
    refute view_body =~ "elmc_new_int(1)"
  end

  test "direct view reuses hoisted min screen dimensions across layout and chrome" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_min_hoist_project", __DIR__)
    out_dir = Path.expand("tmp/direct_min_hoist_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_min_hoist_view_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    view_min_results =
      Regex.scan(~r/const elmc_int_t (native_min_\d+) =/, view_body)
      |> Enum.map(&List.last/1)
      |> Enum.uniq()

    assert length(view_min_results) == 1
    [view_min_result] = view_min_results
    assert Regex.scan(~r/const elmc_int_t native_min_left_\d+ =/, view_body) |> length() == 1
    assert view_body =~ "(#{view_min_result} * 4)"
    assert view_body =~ "native_min_"
    assert view_body =~ "elmc_int_idiv(native_min_"
    assert view_body =~ ", 48)"
  end

  test "direct view uses native packed textOptions without record allocation" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_text_options_project", __DIR__)
    out_dir = Path.expand("tmp/direct_text_options_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_text_options_view_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_native_let_textOptions_"
    assert view_body =~ "ELMC_TEXT_OVERFLOW_SHIFT"
    refute view_body =~ "elmc_record_new_ints"
    refute view_body =~ "elmc_record_update"
  end

  test "direct view inlines boardLayout helper into native record layout fields" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_board_layout_helper_project", __DIR__)
    out_dir = Path.expand("tmp/direct_board_layout_helper_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_board_layout_helper_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: true,
               prune_runtime: true,
               prune_native_wrappers: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    refute view_body =~ "elmc_fn_Main_boardLayout("
    refute generated_c =~ "ElmcValue *elmc_fn_Main_boardLayout("
    refute generated_c =~ "elmc_fn_Pebble_Platform_displayShapeIsRound"
    assert view_body =~ "direct_native_record_layout_x_"
    assert view_body =~ "direct_native_record_layout_cell_"
    assert view_body =~ "ELMC_RENDER_OP_RECT"
    assert Hoist.unused_native_minmax_refs(view_body) == []
  end

  test "direct List.indexedMap over range inlines affine rect through group context" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_indexed_affine_rect_project", __DIR__)
    out_dir = Path.expand("tmp/direct_indexed_affine_rect_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_indexed_map_affine_rect_source())

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_index_"
    assert view_body =~ "(10 + direct_index_"
    assert view_body =~ "elmc_scene_writer_push_cmd"
    refute view_body =~ "elmc_fn_Main_cell_commands_append_native"
  end

  test "direct List.indexedMap with transparent forwarder uses static draw command table" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_indexed_pass_through_project", __DIR__)
    out_dir = Path.expand("tmp/direct_indexed_pass_through_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_indexed_pass_through_source())

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_static_draw_table_"
    refute view_body =~ "_commands_append(direct_call_args_"
    refute view_body =~ "ELMC_TAG_LIST"
  end

  test "direct List.concat of literals uses static draw command table" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_static_table_project", __DIR__)
    out_dir = Path.expand("tmp/direct_static_table_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_static_table_source())

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    assert view_body =~ "direct_static_draw_table_"
    refute view_body =~ "ELMC_TAG_LIST"
  end

  test "direct List.concat of literals avoids list cursor walk in view" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/direct_concat_literal_project", __DIR__)
    out_dir = Path.expand("tmp/direct_concat_literal_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), direct_concat_literal_source())

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    view_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_view_commands_append")

    refute view_body =~ "direct_cursor_"
    refute view_body =~ "ELMC_TAG_LIST"
  end

  test "constructor tag switch requires at least four branches" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/constructor_switch_threshold_project", __DIR__)
    out_dir = Path.expand("tmp/constructor_switch_threshold_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    main_path = Path.join(project_dir, "src/Main.elm")
    File.write!(main_path, File.read!(main_path) <> constructor_switch_threshold_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    small_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_smallTagCase")
    large_body = CCodegenExtract.fn_impl_body(generated_c, "elmc_fn_Main_largeTagCase")

    refute small_body =~ "switch (case_msg_tag_"
    assert large_body =~ "switch (case_msg_tag_"
  end

  test "Result constructors keep boxed case dispatch" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/result_case_boxed_project", __DIR__)
    out_dir = Path.expand("tmp/result_case_boxed_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    File.write!(
      Path.join(project_dir, "src/CoreCompliance.elm"),
      File.read!(Path.join(source_fixture, "src/CoreCompliance.elm"))
    )

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "CoreCompliance",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body =
      generated_c
      |> String.split("static ElmcValue *elmc_fn_CoreCompliance_resultInc")
      |> List.last()
      |> String.split("static ElmcValue *elmc_fn_", parts: 2)
      |> hd()

    refute body =~ "switch (case_msg_tag_"
  end

  test "generated runtime exposes float and bool record index macros" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/record_index_macro_project", __DIR__)
    out_dir = Path.expand("tmp/record_index_macro_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    runtime_h = File.read!(Path.join(out_dir, "runtime/elmc_runtime.h"))

    assert runtime_h =~ "#define ELMC_RECORD_GET_INDEX("
    assert runtime_h =~ "#define ELMC_RECORD_GET_INDEX_FLOAT"
    assert runtime_h =~ "#define ELMC_RECORD_GET_INDEX_BOOL"
  end

  defp direct_indexed_pass_through_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        {}


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode
            (List.indexedMap passThrough
                [ Ui.textInt Resources.DefaultFont { x = 0, y = 0 } 1
                , Ui.textInt Resources.DefaultFont { x = 8, y = 0 } 2
                ]
            )


    passThrough : Int -> Ui.RenderOp -> Ui.RenderOp
    passThrough _ op =
        op
    """
  end

  defp direct_indexed_map_affine_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        {}


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode (List.indexedMap row (List.range 0 3))


    row : Int -> Int -> Ui.RenderOp
    row i n =
        Ui.textInt Resources.DefaultFont { x = i * 10, y = n } n
    """
  end

  defp direct_indexed_map_affine_cells_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { cells : List Int }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { cells = [ 0, 2, 4 ] }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode (List.indexedMap drawCell model.cells)


    drawCell : Int -> Int -> Ui.RenderOp
    drawCell index _ =
        let
            x =
                10 + index * 31
        in
        Ui.group
            (Ui.context
                [ Ui.strokeColor Color.black ]
                [ Ui.rect { x = x, y = 42, w = 28, h = 28 } Color.black ]
            )
    """
  end

  defp direct_indexed_map_affine_cells_fill_skip_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { cells : List Int }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { cells = [ 0, 2 ] }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        let
            layout =
                { x = 10, y = 26, cell = 28, gap = 3 }
        in
        Ui.toUiNode (List.indexedMap (drawCell layout) model.cells)


    drawCell : { x : Int, y : Int, cell : Int, gap : Int } -> Int -> Int -> Ui.RenderOp
    drawCell layout index value =
        let
            x =
                layout.x + modBy 4 index * (layout.cell + layout.gap)

            y =
                layout.y + (index // 4) * (layout.cell + layout.gap)
        in
        Ui.context
            [ Ui.textColor Color.white ]
            [ Ui.rect { x = x, y = y, w = layout.cell, h = layout.cell } Color.black
            , Ui.fillRect { x = x, y = y, w = layout.cell, h = layout.cell } <|
                if value == 0 then
                    Color.white

                else
                    Color.darkGray
            ]
            |> Ui.group
    """
  end

  defp direct_indexed_map_affine_cells_text_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { cells : List Int }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { cells = [ 0, 2, 4 ] }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode (List.indexedMap drawCell model.cells)


    drawCell : Int -> Int -> Ui.RenderOp
    drawCell index value =
        let
            x =
                10 + index * 31

            label =
                if value == 0 then
                    "."

                else
                    String.fromInt value
        in
        Ui.group
            (Ui.context
                [ Ui.strokeColor Color.black
                , Ui.textColor Color.black
                ]
                [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = x + 2, y = 47, w = 24, h = 18 } label
                ]
            )
    """
  end

  defp direct_view_cons_cells_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias BoardLayout =
        { x : Int
        , y : Int
        , cell : Int
        , gap : Int
        }


    type alias Model =
        { cells : List Int
        , best : Int
        }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { cells = [ 0, 2 ], best = 42 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        let
            layout =
                { x = 10, y = 20, cell = 28, gap = 2 }

            chromeOps =
                [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 4, w = 120, h = 14 } ("Best " ++ String.fromInt model.best)
                ]
        in
        Ui.toUiNode
            (Ui.clear Color.white
                :: (chromeOps
                        ++ List.indexedMap (drawCell layout) model.cells
                   )
            )


    drawCell : BoardLayout -> Int -> Int -> Ui.RenderOp
    drawCell layout index _ =
        Ui.rect
            { x = layout.x + modBy 4 index * (layout.cell + layout.gap)
            , y = layout.y + (index // 4) * (layout.cell + layout.gap)
            , w = layout.cell
            , h = layout.cell
            }
            Color.black
    """
  end

  defp direct_text_options_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        { displayShape : Platform.DisplayShape }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { displayShape = Platform.DisplayShapeRound }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        let
            textOptions =
                if Platform.displayShapeIsRound model.displayShape then
                    Ui.alignCenter Ui.defaultTextOptions

                else
                    Ui.defaultTextOptions
        in
        Ui.toUiNode
            [ Ui.text Resources.DefaultFont textOptions { x = 4, y = 4, w = 40, h = 12 } "Hi" ]
    """
  end

  defp direct_board_layout_helper_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias BoardLayout =
        { x : Int
        , y : Int
        , cell : Int
        , gap : Int
        }


    type alias Model =
        { screenW : Int
        , screenH : Int
        , displayShape : Platform.DisplayShape
        , cells : List Int
        }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { screenW = 144, screenH = 168, displayShape = Platform.DisplayShapeRound, cells = [ 0, 2 ] }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        let
            layout =
                boardLayout model
        in
        Ui.toUiNode (List.indexedMap (drawCell layout) model.cells)


    boardLayout : Model -> BoardLayout
    boardLayout model =
        if Platform.displayShapeIsRound model.displayShape then
            let
                diameter =
                    min model.screenW model.screenH

                gap =
                    2

                cell =
                    ((diameter * 2) // 3 - gap * 3) // 4

                boardSize =
                    cell * 4 + gap * 3
            in
            { x = (model.screenW - boardSize) // 2
            , y = (model.screenH - boardSize) // 2
            , cell = cell
            , gap = gap
            }

        else
            { x = 10, y = 26, cell = 28, gap = 3 }


    drawCell : BoardLayout -> Int -> Int -> Ui.RenderOp
    drawCell layout index value =
        let
            x =
                layout.x + modBy 2 index * (layout.cell + layout.gap)

            y =
                layout.y + (index // 2) * (layout.cell + layout.gap)
        in
        Ui.rect { x = x, y = y, w = layout.cell, h = layout.cell } Color.black
    """
  end

  defp direct_min_hoist_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias BoardLayout =
        { x : Int
        , y : Int
        }


    type alias Model =
        { screenW : Int
        , screenH : Int
        , displayShape : Platform.DisplayShape
        }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { screenW = 144, screenH = 168, displayShape = Platform.DisplayShapeRound }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        let
            layout =
                boardLayout model

            chromeOps =
                if Platform.displayShapeIsRound model.displayShape then
                    let
                        textW =
                            (min model.screenW model.screenH * 4) // 9
                    in
                    [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 0, y = 10, w = textW, h = 12 } "Hi" ]

                else
                    []
        in
        Ui.toUiNode (chromeOps ++ [ Ui.rect { x = layout.x, y = layout.y, w = 8, h = 8 } Color.black ])


    boardLayout : Model -> BoardLayout
    boardLayout model =
        if Platform.displayShapeIsRound model.displayShape then
            { x = 0, y = 0 }

        else
            let
                gap =
                    max 3 (min model.screenW model.screenH // 48)
            in
            { x = gap, y = 26 }
    """
  end

  defp direct_display_shape_hoist_view_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias BoardLayout =
        { x : Int
        , y : Int
        , cell : Int
        , gap : Int
        }


    type alias Model =
        { screenW : Int
        , screenH : Int
        , displayShape : Platform.DisplayShape
        }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { screenW = 144, screenH = 168, displayShape = Platform.DisplayShapeRound }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        let
            layout =
                boardLayout model

            chromeOps =
                if Platform.displayShapeIsRound model.displayShape then
                    [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 10, y = 10, w = 40, h = 12 } "Hi" ]

                else
                    []
        in
        Ui.toUiNode (chromeOps ++ [ Ui.rect { x = layout.x, y = layout.y, w = layout.cell, h = layout.cell } Color.black ])


    boardLayout : Model -> BoardLayout
    boardLayout model =
        if Platform.displayShapeIsRound model.displayShape then
            { x = 0, y = 0, cell = 20, gap = 2 }

        else
            { x = 10, y = 26, cell = 28, gap = 3 }
    """
  end

  defp direct_indexed_map_affine_layout_cells_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias BoardLayout =
        { x : Int
        , y : Int
        , cell : Int
        , gap : Int
        }


    type alias Model =
        { cells : List Int }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { cells = [ 0, 2, 4, 8 ] }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        let
            layout =
                { x = 10, y = 20, cell = 28, gap = 2 }
        in
        Ui.toUiNode (List.indexedMap (drawCell layout) model.cells)


    drawCell : BoardLayout -> Int -> Int -> Ui.RenderOp
    drawCell layout index value =
        let
            x =
                layout.x + modBy 4 index * (layout.cell + layout.gap)

            y =
                layout.y + (index // 4) * (layout.cell + layout.gap)

            label =
                if value == 0 then
                    "."

                else
                    String.fromInt value

            textY =
                y + ((layout.cell - 18) // 2)
        in
        Ui.group
            (Ui.context
                [ Ui.strokeColor Color.black ]
                [ Ui.rect { x = x, y = y, w = layout.cell, h = layout.cell } Color.black
                , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = x, y = textY, w = layout.cell, h = 18 } label
                ]
            )
    """
  end

  defp direct_indexed_map_affine_rect_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        {}


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode (List.indexedMap cell (List.range 0 2))


    cell : Int -> Int -> Ui.RenderOp
    cell index _ =
        let
            x =
                10 + index * 31
        in
        Ui.group
            (Ui.context
                [ Ui.strokeColor Color.black ]
                [ Ui.rect { x = x, y = 42, w = 28, h = 28 } Color.black ]
            )
    """
  end

  defp direct_map_affine_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        {}


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode (List.map row (List.range 0 3))


    row : Int -> Ui.RenderOp
    row n =
        Ui.textInt Resources.DefaultFont { x = n * 10, y = 4 } n
    """
  end

  defp direct_static_table_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        {}


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode
            [ Ui.textInt Resources.DefaultFont { x = 0, y = 0 } 1
            , Ui.textInt Resources.DefaultFont { x = 8, y = 0 } 2
            ]
    """
  end

  defp direct_helper_chain_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color


    type alias Model =
        { screenW : Int
        , screenH : Int
        }


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( { screenW = 144, screenH = 168 }, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view model =
        Ui.toUiNode (chrome model)


    chrome model =
        let
            body =
                dial model
        in
        [ Ui.clear Color.black ]
            ++ body


    dial model =
        let
            cx =
                model.screenW // 2

            cy =
                model.screenH // 2

            radius =
                (min model.screenW model.screenH // 2) - 10
        in
        [ Ui.fillCircle { x = cx, y = cy } radius Color.black ]
            ++ ticks cx cy radius


    ticks cx cy radius =
        List.concatMap
            (\\i ->
                [ Ui.line { x = cx, y = cy } { x = cx + i, y = cy + radius } Color.white ]
            )
            (List.range 0 2)
    """
  end

  defp direct_textat_default_options_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        {}


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode
            [ textAt Color.white { x = 4, y = 4, w = 40, h = 16 } "Hi" ]


    textAt : Color.Color -> Ui.Rect -> String -> Ui.RenderOp
    textAt color bounds value =
        Ui.group
            (Ui.context
                [ Ui.textColor color ]
                [ Ui.text Resources.DefaultFont Ui.defaultTextOptions bounds value ]
            )
    """
  end

  defp direct_concatmap_range_ticks_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        {}


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode
            (List.concatMap
                (\\hour ->
                    let
                        inner =
                            pointAt 72 84 60 (angleFromMinute (hour * 60))

                        outer =
                            pointAt 72 84
                                (60
                                    + (if modBy 2 hour == 0 then
                                        5

                                       else
                                        9
                                      )
                                )
                                (angleFromMinute (hour * 60))

                        labelPoint =
                            pointAt 72 84 (60 + 16) (angleFromMinute (hour * 60))

                        label =
                            if hour == 0 then
                                "24"

                            else
                                String.fromInt hour
                    in
                    if modBy 2 hour == 0 then
                        [ Ui.line outer inner Color.white
                        , textAt Color.lightGray { x = labelPoint.x - 6, y = labelPoint.y - 4, w = 12, h = 8 } label
                        ]

                    else
                        [ Ui.line outer inner Color.lightGray ]
                )
                (List.range 0 23)
            )


    textAt : Color.Color -> Ui.Rect -> String -> Ui.RenderOp
    textAt color bounds value =
        Ui.group
            (Ui.context
                [ Ui.textColor color ]
                [ Ui.text Resources.DefaultFont Ui.defaultTextOptions bounds value ]
            )


    pointAt : Int -> Int -> Int -> Int -> Ui.Point
    pointAt cx cy radius angle =
        { x = cx + radius, y = cy + radius }


    angleFromMinute : Int -> Int
    angleFromMinute minute =
        minute * 6 // 60
    """
  end

  defp direct_concatmap_range_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        {}


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode
            (List.concatMap
                (\\hour ->
                    let
                        inner =
                            { x = hour * 4, y = 0 }

                        outer =
                            { x = hour * 4, y = 8 }
                    in
                    [ Ui.line outer inner Color.white
                    , textAt Color.white { x = 0, y = 0, w = 8, h = 8 } (String.fromInt hour)
                    ]
                )
                (List.range 0 3)
            )


    textAt : Color.Color -> Ui.Rect -> String -> Ui.RenderOp
    textAt color bounds value =
        Ui.group
            (Ui.context
                [ Ui.textColor color ]
                [ Ui.text Resources.DefaultFont Ui.defaultTextOptions bounds value ]
            )
    """
  end

  defp direct_map_range_native_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        {}


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode (List.map row (List.range 0 2))


    row : Int -> Ui.RenderOp
    row n =
        Ui.textInt Resources.DefaultFont { x = n * 8, y = 0 } n
    """
  end

  defp direct_concat_literal_source do
    """
    module Main exposing (main)

    import Pebble.Platform as Platform
    import Pebble.Ui as Ui
    import Pebble.Ui.Color as Color
    import Pebble.Ui.Resources as Resources


    type alias Model =
        {}


    type Msg
        = NoOp


    main =
        Platform.application
            { init = init
            , update = update
            , subscriptions = subscriptions
            , view = view
            }


    init _ =
        ( {}, Cmd.none )


    update _ model =
        ( model, Cmd.none )


    subscriptions _ =
        Sub.none


    view _ =
        Ui.toUiNode
            (List.concat
                [ [ Ui.clear Color.white ]
                , [ Ui.textInt Resources.DefaultFont { x = 0, y = 0 } 1
                  , Ui.textInt Resources.DefaultFont { x = 8, y = 0 } 2
                  ]
                ]
            )
    """
  end

  defp constructor_switch_threshold_source do
    """


    type SmallTag
        = TagA
        | TagB


    type LargeTag
        = LargeA
        | LargeB
        | LargeC
        | LargeD


    smallTagCase : SmallTag -> Int
    smallTagCase tag =
        case tag of
            TagA ->
                1

            TagB ->
                2


    largeTagCase : LargeTag -> Int
    largeTagCase tag =
        case tag of
            LargeA ->
                1

            LargeB ->
                2

            LargeC ->
                3

            LargeD ->
                4
    """
  end

  test "game elmtris template compiles displayShapeIsRound case subjects to valid C" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)

    elmtris_main =
      Path.expand("../../ide/priv/project_templates/game_elmtris/src/Main.elm", __DIR__)

    project_dir = Path.expand("tmp/game_elmtris_project", __DIR__)
    out_dir = Path.expand("tmp/game_elmtris_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(elmtris_main))

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    refute generated_c =~ "%{arg:"
    assert generated_c =~ "elmc_fn_Main_gameOverOps"

    File.write!(Path.join(out_dir, "c/game_elmtris_harness.c"), "int main(void) { return 0; }\n")

    cc = System.find_executable("cc") || System.find_executable("gcc")
    assert is_binary(cc)

    {compile_out, compile_code} =
      System.cmd(
        cc,
        [
          "-std=c11",
          "-Wall",
          "-Wextra",
          "-Iruntime",
          "-Iports",
          "-Ic",
          "runtime/elmc_runtime.c",
          "ports/elmc_ports.c",
          "c/elmc_generated.c",
          "c/elmc_worker.c",
          "c/elmc_pebble.c",
          "c/game_elmtris_harness.c",
          "-lm",
          "-o",
          "game_elmtris_harness"
        ],
        cd: out_dir,
        stderr_to_stdout: true
      )

    assert compile_code == 0, compile_out
  end
end
