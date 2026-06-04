defmodule Elmc.CCodegenPatternsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Patterns

  @just_payload_borrow "elmc_maybe_or_tuple_just_payload_borrow"

  test "maybe_unwrap_just_case? recognizes Nothing + bare var branches" do
    branches = [
      %{pattern: %{kind: :constructor, name: "Nothing", bind: nil, arg_pattern: nil}},
      %{pattern: %{kind: :var, name: "piece"}}
    ]

    assert Patterns.maybe_unwrap_just_case?(branches)
    refute Patterns.maybe_unwrap_just_case?([%{pattern: %{kind: :var, name: "piece"}}])
  end

  test "bind_pattern unwraps bare var in Nothing + var Maybe cases" do
    env = Map.put(%{}, :maybe_unwrap_just, true)

    bound =
      env
      |> Patterns.bind_pattern(%{kind: :var, name: "piece"}, "tmp_subject")
      |> Map.fetch!("piece")

    assert bound == "elmc_maybe_or_tuple_just_payload_borrow(tmp_subject)"
  end

  test "bind_pattern leaves bare var unwrapped outside Maybe Nothing + var cases" do
    bound =
      %{}
      |> Patterns.bind_pattern(%{kind: :var, name: "piece"}, "tmp_subject")
      |> Map.fetch!("piece")

    assert bound == "tmp_subject"
  end

  test "Nothing + bare var case codegen uses Just payload for field access" do
    branches = [
      %{
        pattern: %{kind: :constructor, name: "Nothing", bind: nil, arg_pattern: nil},
        expr: %{op: :int_literal, value: 0}
      },
      %{
        pattern: %{kind: :var, name: "piece"},
        expr: %{op: :field_access, arg: %{op: :var, name: "piece"}, field: "y"}
      }
    ]

    case_expr = %{op: :case, subject: "maybePiece", branches: branches}
    env = %{"maybePiece" => "tmp_subject"}

    {code, _out, _counter} = CaseCompile.dispatch(case_expr, env, 0)
    source = IO.iodata_to_binary(code)

    assert source =~ @just_payload_borrow
    refute source =~ "elmc_record_get(tmp_subject, \"y\")"
    refute source =~ "elmc_record_get(maybePiece, \"y\")"

    assert Regex.scan(~r/elmc_maybe_or_tuple_just_payload_borrow\(tmp_subject\)/, source)
           |> length() == 1

    assert source =~ "elmc_record_get(tmp_"
    refute source =~ ~r/elmc_release\(tmp_\d+\);\s*\n\s*\}\s*\n\s*elmc_release\(tmp_2\)/
  end

  test "direct fragment vars allocate retain temp after fragment temps" do
    env = %{
      "fragment" => {:direct_fragment, %{op: :int_literal, value: 42}}
    }

    {code, out, counter} = FunctionCallCompile.compile_var("fragment", env, 0)

    assert out == "tmp_2"
    assert counter == 2
    assert code =~ "ElmcValue *tmp_1 = elmc_new_int(42);"
    assert code =~ "ElmcValue *tmp_2 = elmc_retain(tmp_1);"
    refute code =~ ~r/ElmcValue \*tmp_1 = elmc_retain\(tmp_1\);/
  end

  test "game elmtris template dropStep does not read record fields from Maybe wrapper" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)

    elmtris_main =
      Path.expand("../../ide/priv/project_templates/game_elmtris/src/Main.elm", __DIR__)

    project_dir = Path.expand("tmp/game_elmtris_maybe_case", __DIR__)
    out_dir = Path.expand("tmp/game_elmtris_maybe_codegen", __DIR__)
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

    assert generated_c =~ "elmc_fn_Main_dropStep"
    assert generated_c =~ @just_payload_borrow
    assert generated_c =~ "list_hof_cursor_"
    assert generated_c =~ "elmc_list_nth_maybe"
    refute generated_c =~ "elmc_list_drop("
    refute generated_c =~ ~r/elmc_record_get\(tmp_2, "y"\)/
    refute generated_c =~ ~r/elmc_record_get\(tmp_2, "kind"\)/
    refute generated_c =~ ~r/rec_names_\d+\[5\] = \{ "cell", "gap", "pieceKind"/

    stack_report = File.read!(Path.join(out_dir, "elmc_stack_report.json"))
    assert stack_report =~ "\"functions\""
    assert stack_report =~ "\"summary\""
    assert stack_report =~ "\"code_size_indicators\""
    assert generated_c =~ "list_tuple2_values_"
    assert generated_c =~ "elmc_list_from_tuple2_int_array"
  end

  test "game elmtris init and view run on host pebble shim with basalt launch context" do
    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available for elmtris host harness")

    source_fixture = Path.expand("fixtures/simple_project", __DIR__)

    elmtris_main =
      Path.expand("../../ide/priv/project_templates/game_elmtris/src/Main.elm", __DIR__)

    project_dir = Path.expand("tmp/game_elmtris_host", __DIR__)
    out_dir = Path.expand("tmp/game_elmtris_host_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)
    File.write!(Path.join(project_dir, "src/Main.elm"), File.read!(elmtris_main))

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: true
             })

    makefile = File.read!(Path.join(out_dir, "Makefile"))
    assert makefile =~ "-ffunction-sections"
    assert makefile =~ "-fdata-sections"
    assert makefile =~ "-Wl,--gc-sections"

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))
    assert generated_c =~ "elmc_list_replace_nth_int"
    refute generated_c =~ "elmc_list_indexed_map("
    assert generated_c =~ "elmc_case_branch_helper_Main_rotateActive"
    assert generated_c =~ "elmc_let_body_helper_Main_lockPiece"
    assert generated_c =~ "elmc_record_literal_helper_Main_freshModel"
    assert generated_c =~ "elmc_record_update_helper_Main_lockPiece"

    harness_path = Path.join(out_dir, "c/elmtris_host_harness.c")

    File.write!(
      harness_path,
      """
      #include "elmc_pebble.h"
      #include <stdio.h>

      static ElmcValue *basalt_launch_context(void) {
        ElmcValue *reason = elmc_new_int(2);
        ElmcValue *watch_model = elmc_new_string("");
        ElmcValue *watch_profile_id = elmc_new_string("");
        ElmcValue *width = elmc_new_int(144);
        ElmcValue *height = elmc_new_int(168);
        ElmcValue *shape = elmc_new_int(2);
        ElmcValue *color_mode = elmc_new_string("Color");
        const char *screen_names[] = {"color_mode", "height", "shape", "width"};
        ElmcValue *screen_values[] = {color_mode, height, shape, width};
        ElmcValue *screen = elmc_record_new_take(4, screen_names, screen_values);
        ElmcValue *has_microphone = elmc_new_int(0);
        ElmcValue *has_compass = elmc_new_int(0);
        ElmcValue *supports_health = elmc_new_int(0);
        const char *names[] = {
          "hasCompass", "hasMicrophone", "reason", "screen",
          "supportsHealth", "watchModel", "watchProfileId"
        };
        ElmcValue *values[] = {
          has_compass, has_microphone, reason, screen,
          supports_health, watch_model, watch_profile_id
        };
        return elmc_record_new_take(7, names, values);
      }

      int main(void) {
        ElmcPebbleApp app = {0};
        ElmcValue *flags = basalt_launch_context();
        if (elmc_pebble_init(&app, flags) != 0) {
          fprintf(stderr, "init failed\\n");
          return 2;
        }
        elmc_release(flags);

        ElmcPebbleDrawCmd cmds[128] = {0};
        int n = elmc_pebble_view_commands(&app, cmds, 128);
        if (n < 4) {
          fprintf(stderr, "expected view commands, got %d\\n", n);
          return 3;
        }
        ElmcValue *model = elmc_worker_model(&app.worker);
        if (!model || ELMC_RECORD_GET_INDEX_INT(model, 7) < 0) {
          fprintf(stderr, "expected active piece\\n");
          elmc_release(model);
          return 4;
        }
        elmc_release(model);
        elmc_pebble_deinit(&app);
        printf("ok view_commands=%d\\n", n);
        return 0;
      }
      """
    )

    binary_path = Path.join(out_dir, "elmtris_host_harness")

    {compile_out, compile_code} =
      System.cmd(cc, [
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-I#{Path.join(out_dir, "runtime")}",
        "-I#{Path.join(out_dir, "ports")}",
        "-I#{Path.join(out_dir, "c")}",
        Path.join(out_dir, "runtime/elmc_runtime.c"),
        Path.join(out_dir, "ports/elmc_ports.c"),
        Path.join(out_dir, "c/elmc_generated.c"),
        Path.join(out_dir, "c/elmc_worker.c"),
        Path.join(out_dir, "c/elmc_pebble.c"),
        harness_path,
        "-o",
        binary_path
      ])

    assert compile_code == 0, compile_out

    {run_out, run_code} = System.cmd(binary_path, [])
    assert run_code == 0, run_out
    assert String.contains?(run_out, "ok view_commands=")
  end
end
