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

    File.write!(Path.join(out_dir, "c/complete_basics_harness.c"), "int main(void) { return 0; }\n")

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

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

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
    refute native_case_body =~ "->tag == ELMC_TAG_INT"
    refute native_case_body =~ "elmc_as_int(native_let_caseSubject_"
    refute native_case_body =~ "elmc_new_int(native_mod_"
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

    assert native_bool_body =~ "if (elmc_record_get_bool(model, \"isRound\"))"
    refute native_bool_body =~ "elmc_record_get(model, \"isRound\")"
    refute native_bool_body =~ "elmc_as_int(tmp_"
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

    assert native_min_body =~ "elmc_record_get_int(model, \"screenW\")"
    assert native_min_body =~ "elmc_record_get_int(model, \"screenH\")"
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
    File.write!(main_path, File.read!(main_path) <> native_text_arg_source())

    assert {:ok, _result} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~
             "static int elmc_fn_Main_nativeTextAt_commands_append_native(elmc_int_t color, const char *value"

    body =
      generated_c
      |> String.split("static int elmc_fn_Main_nativeTextLiteral_commands_append")
      |> List.last()

    [literal_body | _rest] = String.split(body, "int elmc_fn_", parts: 2)

    assert literal_body =~
             "elmc_fn_Main_nativeTextAt_commands_append_native(255, \"Direct\""

    refute literal_body =~ "elmc_new_string(\"Direct\")"
    refute literal_body =~ "elmc_new_int(255)"
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

  test "runtime extracts constructor-shaped UiNode returned from user helpers" do
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

    File.write!(Path.join(out_dir, "c/top_level_function_reference_harness.c"), top_level_function_reference_harness_source())

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
      System.cmd(Path.join(out_dir, "top_level_function_reference_harness"), [], stderr_to_stdout: true)

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
    """
  end

  defp native_literal_division_source do
    """


    nativeLiteralDivision : Int -> String
    nativeLiteralDivision value =
        String.fromInt (value * 328 // 100)
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


    nativeTextLiteral : List PebbleUi.RenderOp
    nativeTextLiteral =
        nativeTextAt PebbleColor.white "Direct"
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
