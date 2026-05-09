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
    assert generated_c =~ "elmc_list_cons"

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

    add_to_ui_node_helper!(Path.join(project_dir, "src/Pebble/Ui.elm"))
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

  defp add_to_ui_node_helper!(path) do
    source = File.read!(path)

    source =
      source
      |> String.replace(
        "    , textLabel\n    , window\n",
        "    , textLabel\n    , toUiNode\n    , window\n"
      )
      |> String.replace(
        "canvasLayer id ops =\n    CanvasLayer id ops\n",
        """
        canvasLayer id ops =
            CanvasLayer id ops


        toUiNode : List RenderOp -> UiNode
        toUiNode ops =
            windowStack
                [ window 1
                    [ canvasLayer 1 ops ]
                ]
        """
      )

    File.write!(path, source)
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
end
