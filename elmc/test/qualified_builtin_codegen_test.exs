defmodule Elmc.QualifiedBuiltinCodegenTest do
  use ExUnit.Case

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
    assert generated_c =~ "elmc_value_equal"

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

    body =
      generated_c
      |> String.split("static ElmcValue *elmc_fn_Main_typedBounds_native")
      |> List.last()

    [typed_bounds_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    assert typed_bounds_body =~ "elmc_record_new_ints"
    refute typed_bounds_body =~ "elmc_retain(x)"
    refute typed_bounds_body =~ "elmc_retain(y)"

    access_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_typedBoundsAccess")
      |> List.last()

    [typed_access_body | _rest] = String.split(access_body, "ElmcValue *elmc_fn_", parts: 2)

    assert typed_access_body =~ "elmc_record_get_index("
    assert typed_access_body =~ "2 /* x */"
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

    body =
      generated_c
      |> String.split("static ElmcValue *elmc_fn_Main_nativeIntCase_native")
      |> List.last()

    [native_case_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    assert native_case_body =~ "elmc_int_t native_let_caseSubject_"
    assert native_case_body =~ "switch (native_let_caseSubject_"
    assert native_case_body =~ "case 0:"
    assert native_case_body =~ "default:"
    refute native_case_body =~ " = elmc_int_zero();\n  switch"
    assert native_case_body =~ " = elmc_new_int(1);"
    assert native_case_body =~ " = elmc_new_int(2);"
    refute native_case_body =~ "elmc_release(tmp_"
    refute native_case_body =~ "->tag == ELMC_TAG_INT"
    refute native_case_body =~ "elmc_as_int(native_let_caseSubject_"
    refute native_case_body =~ "elmc_new_int(native_mod_"

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_new_int\(1\);\s+tmp_\d+ = tmp_\d+;/,
             native_case_body
           )
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

    body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_nativeIntCaseString")
      |> List.last()

    [case_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    assert case_body =~ "switch (month)"
    assert case_body =~ "case 1:"
    assert case_body =~ " = elmc_new_string(\"Jan\");"
    assert case_body =~ "case 2:"
    assert case_body =~ " = elmc_new_string(\"Feb\");"

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

    body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_boxedDirectionString")
      |> List.last()

    [case_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    assert Regex.match?(~r/ElmcValue \*tmp_\d+;\s+if \(/, case_body)
    assert case_body =~ " = elmc_new_string(\"N\");"
    assert case_body =~ " = elmc_new_string(\"S\");"
    refute case_body =~ " = elmc_int_zero();"
    refute Regex.match?(~r/elmc_release\(tmp_\d+\);\s+tmp_\d+ = tmp_\d+;/, case_body)

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_new_string\(\"N\"\);\s+tmp_\d+ = tmp_\d+;/,
             case_body
           )
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

    body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_nativeBoolField")
      |> List.last()

    [native_bool_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    assert native_bool_body =~ "if (elmc_record_get_index_bool(model, 0 /* isRound */))"
    refute native_bool_body =~ "elmc_record_get(model, \"isRound\")"
    refute native_bool_body =~ "elmc_as_int(tmp_"

    helper_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_nativeBoolHelperColor")
      |> List.last()

    [native_bool_helper_body | _rest] = String.split(helper_body, "ElmcValue *elmc_fn_", parts: 2)

    assert native_bool_helper_body =~ "elmc_as_bool(tmp_"
    assert native_bool_helper_body =~ "ElmcValue *tmp_"
    assert native_bool_helper_body =~ " = elmc_retain(tmp_"
    refute native_bool_helper_body =~ "if (elmc_as_int(tmp_"
    refute native_bool_helper_body =~ " ? elmc_retain(tmp_"
    assert native_bool_helper_body =~ " = elmc_new_int(192);"
    assert native_bool_helper_body =~ " = elmc_new_int(255);"

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_new_int\(192\);\s+tmp_\d+ = tmp_\d+;/,
             native_bool_helper_body
           )

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_int_zero\(\);\s+if \(native_b_\d+\)/,
             native_bool_helper_body
           )

    mixed_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_nativeBoolMixedBranches")
      |> List.last()

    [native_bool_mixed_body | _rest] = String.split(mixed_body, "ElmcValue *elmc_fn_", parts: 2)

    assert native_bool_mixed_body =~ "ElmcValue *tmp_"
    assert native_bool_mixed_body =~ "if ((value < 0))"
    assert native_bool_mixed_body =~ "elmc_new_int(1)"
    assert native_bool_mixed_body =~ "elmc_new_bool(elmc_value_equal("

    refute Regex.match?(
             ~r/ElmcValue \*tmp_\d+ = elmc_int_zero\(\);\s+if \(\(value < 0\)\)/,
             native_bool_mixed_body
           )

    [_, result_var] =
      Regex.run(~r/ElmcValue \*(tmp_\d+);\s+if \(\(value < 0\)\)/, native_bool_mixed_body)

    refute native_bool_mixed_body =~ "elmc_release(#{result_var});"

    maybe_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_nativeBoolMaybeBranchReuse")
      |> List.last()

    [native_bool_maybe_body | _rest] = String.split(maybe_body, "ElmcValue *elmc_fn_", parts: 2)

    assert native_bool_maybe_body =~ "if (elmc_as_bool(flag))"

    [_, maybe_result_var] =
      Regex.run(
        ~r/ElmcValue \*(tmp_\d+);\s+if \(elmc_as_bool\(flag\)\)/,
        native_bool_maybe_body
      )

    refute native_bool_maybe_body =~ "ElmcValue *#{maybe_result_var} = elmc_int_zero();"
    refute native_bool_maybe_body =~ "elmc_release(#{maybe_result_var});"
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

    body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_nativeMinRecordFields")
      |> List.last()

    [native_min_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    assert native_min_body =~ "ELMC_RECORD_GET_INDEX_INT(model, 1 /* screenW */)"
    assert native_min_body =~ "ELMC_RECORD_GET_INDEX_INT(model, 0 /* screenH */)"
    assert native_min_body =~ "native_min_"
    refute native_min_body =~ "elmc_basics_min"
    refute native_min_body =~ "elmc_record_get(model, \"screenW\")"
    refute native_min_body =~ "elmc_record_get(model, \"screenH\")"
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

    body =
      generated_c
      |> String.split("static ElmcValue *elmc_fn_Main_nativeStringFromInt_native")
      |> List.last()

    [native_string_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    assert native_string_body =~ "elmc_string_from_native_int((value + 1))"
    refute native_string_body =~ "elmc_new_int((value + 1))"
    refute native_string_body =~ "elmc_string_from_int"

    append_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_nativeStringAppend")
      |> List.last()

    [native_append_body | _rest] = String.split(append_body, "ElmcValue *elmc_fn_", parts: 2)

    assert native_append_body =~ "elmc_string_append_native(\"0\", native_string_"
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

    body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_boxedStringIf")
      |> List.last()

    [boxed_string_if_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

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

    assert Regex.match?(
             ~r/const char \*native_string_\d+ = \(const char \*\)tmp_\d+->payload;/,
             boxed_string_if_body
           )

    assert boxed_string_if_body =~ "elmc_string_append_native(native_string_"
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
    File.write!(main_path, File.read!(main_path) <> native_maybe_default_string_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_nativeMaybeDefaultString")
      |> List.last()

    [maybe_string_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    assert maybe_string_body =~ "native_maybe_default_"
    assert maybe_string_body =~ "elmc_record_get_index_maybe_int(model, 0 /* batteryLevel */, 0)"
    assert maybe_string_body =~ "elmc_string_from_native_int(native_maybe_default_"
    refute maybe_string_body =~ "elmc_record_get(model, \"batteryLevel\")"
    refute maybe_string_body =~ "elmc_int_zero()"
    refute maybe_string_body =~ "elmc_maybe_with_default("
    refute maybe_string_body =~ "elmc_string_from_int"

    arg_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_nativeMaybeDefaultStringArg")
      |> List.last()

    [maybe_arg_body | _rest] = String.split(arg_body, "ElmcValue *elmc_fn_", parts: 2)

    assert maybe_arg_body =~ "native_maybe_default_"
    assert maybe_arg_body =~ "elmc_record_get_index_maybe_int(model, 0 /* batteryLevel */, 0)"
    assert maybe_arg_body =~ "elmc_string_from_native_int(native_maybe_default_"
    refute maybe_arg_body =~ "elmc_record_get(model, \"batteryLevel\")"
    refute maybe_arg_body =~ "elmc_int_zero()"
    refute maybe_arg_body =~ "elmc_maybe_with_default("
    refute maybe_arg_body =~ "elmc_string_from_int"
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

    body =
      generated_c
      |> String.split("static ElmcValue *elmc_fn_Main_nativeHelperArgLet_native")
      |> List.last()

    [native_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    assert native_body =~ "elmc_int_t native_let_moonPhaseY_"
    assert native_body =~ "elmc_fn_Main_nativeIntSink_native(native_let_moonPhaseY_"
    refute native_body =~ "elmc_new_int((cy +"

    call_body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_typedIntReturnReuse")
      |> List.last()

    [typed_call_body | _rest] = String.split(call_body, "ElmcValue *elmc_fn_", parts: 2)

    assert typed_call_body =~ "ElmcValue *tmp_"
    assert typed_call_body =~ "elmc_fn_Main_opaqueStringLength"
    assert typed_call_body =~ "const elmc_int_t native_let_hours_"
    assert typed_call_body =~ "elmc_fn_Main_nativeIntSink_native(native_let_hours_"
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

    body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_enumUnitString")
      |> List.last()

    [enum_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    assert enum_body =~ "elmc_as_int(unit) == 2"
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

    body =
      generated_c
      |> String.split("static ElmcValue *elmc_fn_Main_nativeAbsNegate_native")
      |> List.last()

    [native_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

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

    body =
      generated_c
      |> String.split("static ElmcValue *elmc_fn_Main_nativeLiteralDivision_native")
      |> List.last()

    [native_div_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    assert native_div_body =~ "elmc_string_from_native_int(((value * 328) / 100))"
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

    body =
      generated_c
      |> String.split("static int elmc_fn_Main_helperRecordFieldOps_commands_append_native")
      |> List.last()

    [use_body | _rest] = String.split(body, "int elmc_fn_", parts: 2)

    refute use_body =~ "elmc_fn_Main_helperRecordFieldBounds"
    assert use_body =~ "out_cmds[*count].p0 = (x + 1);"
    assert use_body =~ "out_cmds[*count].p3 = 12;"
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
             "static int elmc_fn_Main_nativeTextAt_commands_append_native(const elmc_int_t color, const char * const value"

    assert generated_c =~
             "static int elmc_fn_Main_nativeTextAtAlias_commands_append_native(const elmc_int_t color, const char * const value"

    assert generated_c =~
             "static int elmc_fn_Main_nativeTextAtExplicitAlias_commands_append_native(const elmc_int_t color, const char * const value"

    assert generated_c =~
             "static int elmc_fn_Main_nativeTextAtExposedType_commands_append_native(const elmc_int_t color, const char * const value"

    body =
      generated_c
      |> String.split("static int elmc_fn_Main_nativeTextLiteral_commands_append")
      |> List.last()

    [literal_body | _rest] = String.split(body, "int elmc_fn_", parts: 2)

    assert literal_body =~
             "elmc_fn_Main_nativeTextAt_commands_append_native(255, \"Direct\""

    refute literal_body =~ "elmc_new_string(\"Direct\")"
    refute literal_body =~ "elmc_new_int(255)"

    let_body =
      generated_c
      |> String.split("static int elmc_fn_Main_nativeTextLet_commands_append")
      |> List.last()

    [native_let_body | _rest] = String.split(let_body, "int elmc_fn_", parts: 2)

    assert native_let_body =~ "char native_string_buf_"
    assert native_let_body =~ "snprintf(native_string_buf_"
    assert native_let_body =~ "? \"Zero\" : native_string_"
    refute native_let_body =~ "elmc_new_string(\"Zero\")"
    refute native_let_body =~ "elmc_string_from_native_int(value)"
    refute native_let_body =~ "ELMC_TAG_STRING"

    alias_body =
      generated_c
      |> String.split("static int elmc_fn_Main_nativeTextAliasIf_commands_append")
      |> List.last()

    [native_alias_body | _rest] = String.split(alias_body, "int elmc_fn_", parts: 2)

    assert native_alias_body =~ "const elmc_int_t direct_native_let_color_"

    assert native_alias_body =~
             "elmc_fn_Main_nativeTextAtAlias_commands_append_native(direct_native_let_color_"

    refute native_alias_body =~ "elmc_new_int(192)"
    refute native_alias_body =~ "elmc_new_int(255)"
    refute native_alias_body =~ "? elmc_retain(tmp_"

    explicit_alias_body =
      generated_c
      |> String.split("static int elmc_fn_Main_nativeTextExplicitAliasIf_commands_append")
      |> List.last()

    [native_explicit_alias_body | _rest] =
      String.split(explicit_alias_body, "int elmc_fn_", parts: 2)

    assert native_explicit_alias_body =~ "const elmc_int_t direct_native_let_color_"

    assert native_explicit_alias_body =~
             "elmc_fn_Main_nativeTextAtExplicitAlias_commands_append_native(direct_native_let_color_"

    refute native_explicit_alias_body =~ "elmc_new_int(192)"
    refute native_explicit_alias_body =~ "elmc_new_int(255)"
    refute native_explicit_alias_body =~ "? elmc_retain(tmp_"

    exposed_type_body =
      generated_c
      |> String.split("static int elmc_fn_Main_nativeTextExposedTypeIf_commands_append")
      |> List.last()

    [native_exposed_type_body | _rest] =
      String.split(exposed_type_body, "int elmc_fn_", parts: 2)

    assert native_exposed_type_body =~ "const elmc_int_t direct_native_let_color_"

    assert native_exposed_type_body =~
             "elmc_fn_Main_nativeTextAtExposedType_commands_append_native(direct_native_let_color_"

    refute native_exposed_type_body =~ "elmc_new_int(192)"
    refute native_exposed_type_body =~ "elmc_new_int(255)"
    refute native_exposed_type_body =~ "? elmc_retain(tmp_"

    bounds_body =
      generated_c
      |> String.split("static int elmc_fn_Main_nativeTextBounds_commands_append_native")
      |> List.last()

    [native_bounds_body | _rest] = String.split(bounds_body, "int elmc_fn_", parts: 2)

    assert native_bounds_body =~
             "out_cmds[*count].p1 = ELMC_RECORD_GET_INDEX_INT(bounds, 2 /* x */)"

    assert native_bounds_body =~
             "out_cmds[*count].p2 = ELMC_RECORD_GET_INDEX_INT(bounds, 3 /* y */)"

    assert native_bounds_body =~
             "out_cmds[*count].p3 = ELMC_RECORD_GET_INDEX_INT(bounds, 1 /* w */)"

    assert native_bounds_body =~
             "out_cmds[*count].p4 = ELMC_RECORD_GET_INDEX_INT(bounds, 0 /* h */)"

    refute native_bounds_body =~ "out_cmds[*count].p1 = 0;"
    refute native_bounds_body =~ "out_cmds[*count].p3 = 0;"

    helper_body =
      generated_c
      |> String.split("static int elmc_fn_Main_nativeTextFromHelper_commands_append_native")
      |> List.last()

    [native_helper_body | _rest] = String.split(helper_body, "int elmc_fn_", parts: 2)

    assert native_helper_body =~ "ElmcValue *tmp_"
    assert native_helper_body =~ "const char *native_string_"
    assert native_helper_body =~ "= (const char *)tmp_"
    refute native_helper_body =~ "ELMC_TAG_STRING"
    refute native_helper_body =~ "? (const char *)tmp_"
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

    body =
      generated_c
      |> String.split("static int elmc_fn_Main_directNativeLetBounds_commands_append_native")
      |> List.last()

    [use_body | _rest] = String.split(body, "int elmc_fn_", parts: 2)

    assert use_body =~ "elmc_int_t direct_native_let_x_"
    assert use_body =~ "elmc_int_t direct_native_let_y_"
    assert use_body =~ "out_cmds[*count].p1 = direct_native_let_x_"
    assert use_body =~ "out_cmds[*count].p2 = direct_native_let_y_"
    refute use_body =~ "elmc_new_int((screenW - 64))"
    refute use_body =~ "elmc_new_int((screenH - 36))"
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

    body =
      generated_c
      |> String.split("static int elmc_fn_Main_directNativeIfLet_commands_append_native")
      |> List.last()

    [use_body | _rest] = String.split(body, "int elmc_fn_", parts: 2)

    assert use_body =~ "elmc_int_t native_if_"
    assert use_body =~ "native_negate_"
    assert use_body =~ "out_cmds[*count].p0 = (cx + direct_native_let_offset_"
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

    body =
      generated_c
      |> String.split("static int elmc_fn_Main_directNativeBoolCondition_commands_append")
      |> List.last()

    [condition_body | _rest] = String.split(body, "int elmc_fn_", parts: 2)

    assert condition_body =~ "if (elmc_as_bool(enabled))"
    assert condition_body =~ "elmc_generated_draw_init(&out_cmds[*count], ELMC_PEBBLE_DRAW_CLEAR)"
    refute condition_body =~ "elmc_generated_draw_init(&out_cmds[*count], 2)"
    refute condition_body =~ "elmc_retain(enabled)"
    refute condition_body =~ "elmc_release(enabled)"
    refute condition_body =~ "ElmcValue *tmp_"

    empty_then_body =
      generated_c
      |> String.split("static int elmc_fn_Main_directEmptyThenCondition_commands_append")
      |> List.last()

    [empty_then_condition_body | _rest] = String.split(empty_then_body, "int elmc_fn_", parts: 2)

    assert empty_then_condition_body =~ "if (!(elmc_as_bool(enabled)))"
    refute empty_then_condition_body =~ "} else {"

    typed_int_body =
      generated_c
      |> String.split("static int elmc_fn_Main_directTypedIntResultReuse_commands_append")
      |> List.last()

    [typed_int_direct_body | _rest] = String.split(typed_int_body, "int elmc_fn_", parts: 2)

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

    body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_wildcardCaseCondition")
      |> List.last()

    [case_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    refute case_body =~ "if (1)"
    refute case_body =~ "else if (1)"
    assert case_body =~ "else {"

    direct_body =
      generated_c
      |> String.split("static int elmc_fn_Main_wildcardCaseConditionOps_commands_append")
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

    body =
      generated_c
      |> String.split("static int elmc_fn_Main_directMaybeDefaultHelperArg_commands_append")
      |> List.last()

    [helper_arg_body | _rest] = String.split(body, "int elmc_fn_", parts: 2)

    assert helper_arg_body =~ "elmc_record_get_index_maybe_int(model, 0 /* moonsetMin */, 720)"
    assert helper_arg_body =~ "= (direct_native_let_moonset_"
    refute helper_arg_body =~ "elmc_new_int(720)"
    refute helper_arg_body =~ "elmc_record_get(model, \"moonsetMin\")"
    refute helper_arg_body =~ "elmc_maybe_with_default"
    refute helper_arg_body =~ "elmc_fn_Main_helperAngle_native"
    assert helper_arg_body =~ "// inlined Main.helperAngle"

    sun_body =
      generated_c
      |> String.split("static int elmc_fn_Main_directSunWindowFields_commands_append")
      |> List.last()

    [sun_window_body | _rest] = String.split(sun_body, "int elmc_fn_", parts: 2)

    assert sun_window_body =~ "ELMC_RECORD_GET_INDEX_INT("
    assert sun_window_body =~ "0 /* sunriseMin */"
    assert sun_window_body =~ "1 /* sunsetMin */"
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

    marker =
      "const elmc_int_t nativeHourForLambda = (argc > 0 && args[0]) ? elmc_as_int(args[0]) : 0;"

    assert generated_c =~ marker
    [_before, after_marker] = String.split(generated_c, marker, parts: 2)
    [lambda_body | _rest] = String.split(marker <> after_marker, "\n}\n\nstatic", parts: 2)

    refute lambda_body =~ "ElmcValue *nativeHourForLambda ="
    refute lambda_body =~ "nativeHourForLambda ? elmc_as_int(nativeHourForLambda) : 0"
    refute lambda_body =~ "native_mod_base_"
    refute lambda_body =~ "!= 0) {"
    assert lambda_body =~ "elmc_string_from_native_int(nativeHourForLambda)"
    assert lambda_body =~ "nativeHourForLambda % 2"
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

    body =
      generated_c
      |> String.split("ElmcValue *elmc_fn_Main_nativeBoxedRecordCompare")
      |> List.last()

    [compare_body | _rest] = String.split(body, "ElmcValue *elmc_fn_", parts: 2)

    refute compare_body =~ "elmc_basics_compare"
    refute compare_body =~ "elmc_new_int(720)"
    assert compare_body =~ "elmc_as_int("
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
             "static ElmcValue *elmc_fn_Main_nativeOnlyHelper_native(const elmc_int_t value)"

    assert generated_c =~ "elmc_fn_Main_nativeOnlyHelper_native(7)"
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

  test "direct render only builds omit generic render helpers" do
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
    assert generated_c =~ "ElmcValue *elmc_fn_Main_init("
    assert generated_c =~ "ElmcValue *elmc_fn_Main_update("
    assert generated_c =~ "ElmcValue *elmc_fn_Main_subscriptions("

    refute generated_c =~ "ElmcValue *elmc_fn_Main_view(ElmcValue"
    refute generated_c =~ "ElmcValue *elmc_fn_Main_statusDraw(ElmcValue"
    refute generated_c =~ "ElmcValue *elmc_fn_Main_counterDraw(ElmcValue"
    refute generated_c =~ "elmc_fn_Pebble_Ui_windowStack"
    refute generated_c =~ "elmc_fn_Pebble_Ui_path"

    assert pebble_c =~ "#if !defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)\n  int count = 0;"
    assert pebble_c =~ "#if defined(ELMC_HAVE_DIRECT_COMMANDS_MAIN_VIEW)\n  (void)app;"
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
    assert generated_c =~ "elmc_new_int(1000)"
    assert generated_c =~ "elmc_new_int(1001)"
    assert generated_c =~ "elmc_new_int(1002)"

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

  test "top-level function references compile as closures for indexedMap views" do
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
    assert generated_c =~ "elmc_closure_new"

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
      ElmcValue *flags = elmc_new_int(0);
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
        Ui.text Resources.DefaultFont { x = index * 10, y = 0, w = 10, h = 10 } (String.fromInt value)


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
      ElmcValue *flags = elmc_new_int(0);
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
        cmds[16].kind == ELMC_PEBBLE_DRAW_TEXT &&
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
      ElmcValue *flags = elmc_new_int(0);
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
      ElmcValue *flags = elmc_new_int(0);
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
                [ PebbleUi.text UiResources.DefaultFont { x = 1, y = 2, w = 30, h = 12 } value ]
            )


    nativeTextAtAlias : PebbleColor.Color -> String -> List PebbleUi.RenderOp
    nativeTextAtAlias color value =
        PebbleUi.group
            (PebbleUi.context
                [ PebbleUi.textColor color ]
                [ PebbleUi.text UiResources.DefaultFont { x = 1, y = 2, w = 30, h = 12 } value ]
            )


    nativeTextAtExplicitAlias : Color.Color -> String -> List PebbleUi.RenderOp
    nativeTextAtExplicitAlias color value =
        PebbleUi.group
            (PebbleUi.context
                [ PebbleUi.textColor color ]
                [ PebbleUi.text UiResources.DefaultFont { x = 1, y = 2, w = 30, h = 12 } value ]
            )


    nativeTextAtExposedType : Color -> String -> List PebbleUi.RenderOp
    nativeTextAtExposedType color value =
        PebbleUi.group
            (PebbleUi.context
                [ PebbleUi.textColor color ]
                [ PebbleUi.text UiResources.DefaultFont { x = 1, y = 2, w = 30, h = 12 } value ]
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
        PebbleUi.text UiResources.DefaultFont bounds value


    nativeTextHelper : Int -> String
    nativeTextHelper value =
        String.fromInt value


    nativeTextFromHelper : Int -> List PebbleUi.RenderOp
    nativeTextFromHelper value =
        PebbleUi.text UiResources.DefaultFont { x = 1, y = 2, w = 30, h = 12 } (nativeTextHelper value)
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
        [ PebbleUi.text UiResources.DefaultFont { x = x, y = y, w = 60, h = 18 } "Alt" ]
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

  defp unreachable_direct_command_source do
    """


    unreachableDirectOps : List PebbleUi.RenderOp
    unreachableDirectOps =
        [ PebbleUi.clear PebbleColor.black
        , PebbleUi.line { x = 0, y = 0 } { x = 10, y = 10 } PebbleColor.white
        ]
    """
  end
end
