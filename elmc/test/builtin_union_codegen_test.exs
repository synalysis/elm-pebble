defmodule Elmc.BuiltinUnionCodegenTest do
  use ExUnit.Case, async: true

  test "Pebble.Light helpers emit compact backlight commands" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/builtin_union_light_project", __DIR__)
    out_dir = Path.expand("tmp/builtin_union_light_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main = """
    module Main exposing (main)

    import Pebble.Cmd as Cmd
    import Pebble.Light as Light
    import Pebble.Platform as Platform

    main : Platform.Program () () ()
    main =
        Platform.worker
            { init = \\flags -> ( (), Cmd.batch [ Light.interaction, Light.disable, Light.enable ] )
            , update = \\_ _ -> ( (), Platform.Cmd.none )
            , subscriptions = \\_ -> Platform.Sub.none
            , view = \\_ -> Platform.Cmd.none
            }
    """

    File.write!(Path.join(project_dir, "src/Main.elm"), main)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main"
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_cmd1(ELMC_PEBBLE_CMD_BACKLIGHT, 0)"
    assert generated_c =~ "elmc_cmd1(ELMC_PEBBLE_CMD_BACKLIGHT, 1)"
    assert generated_c =~ "elmc_cmd1(ELMC_PEBBLE_CMD_BACKLIGHT, 2)"
    refute generated_c =~ "elmc_cmd_backlight_from_maybe("
    refute generated_c =~ "elmc_maybe_nothing()"
    refute generated_c =~ "elmc_maybe_just("
  end

  test "Just and Ok payload constructors use typed runtime allocators" do
    source_fixture = Path.expand("fixtures/simple_project", __DIR__)
    project_dir = Path.expand("tmp/builtin_union_payload_project", __DIR__)
    out_dir = Path.expand("tmp/builtin_union_payload_codegen", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.dirname(project_dir))
    File.cp_r!(source_fixture, project_dir)

    main = """
    module Main exposing (main, sample)

    import Pebble.Platform as Platform

    sample : ( Maybe Int, Result Int String )
    sample =
        ( Just 1, Ok 2 )
    """

    File.write!(Path.join(project_dir, "src/Main.elm"), main)

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    assert generated_c =~ "elmc_maybe_just("
    assert generated_c =~ "elmc_result_ok("
  end
end
