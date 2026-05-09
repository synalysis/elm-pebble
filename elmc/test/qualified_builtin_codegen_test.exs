defmodule Elmc.QualifiedBuiltinCodegenTest do
  use ExUnit.Case

  test "qualified Basics operators are lowered as builtins" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    out_dir = Path.expand("tmp/qualified_builtin_codegen", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _result} = Elmc.compile(project_dir, %{out_dir: out_dir, entry_module: "Main"})

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    refute generated_c =~ "elmc_fn_Basics___mul__"
    refute generated_c =~ "elmc_fn_Basics___add__"
    refute generated_c =~ "elmc_fn_Basics___idiv__"
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
end
