defmodule Elmc.TutorialCompleteMinuteCodegenTest do
  use ExUnit.Case, async: false

  alias Elmc.Test.CCodegenExtract

  @source_template Path.expand("../../ide/priv/project_templates/watchface_tutorial_complete", __DIR__)

  test "MinuteChanged weather request passes union tuple to sendWatchToPhone" do
    project_dir = Path.expand("tmp/tutorial_complete_minute_codegen_project", __DIR__)
    out_dir = Path.expand("tmp/tutorial_complete_minute_codegen_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.cp_r!(@source_template, project_dir)

    File.write!(
      Path.join(project_dir, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => [
          "src",
          "protocol/src",
          "../../../../packages/elm-pebble/elm-watch/src"
        ],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3", "elm/time" => "1.0.0"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: false,
               prune_runtime: false,
               prune_native_wrappers: true,
               pebble_int32: true,
               strip_dead_code: true
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    minute_changed =
      generated
      |> CCodegenExtract.fn_body("elmc_fn_Main_update")
      |> String.split("case ELMC_PEBBLE_MSG_MINUTECHANGED:")
      |> Enum.at(1)
      |> then(fn rest -> rest |> String.split("case ") |> hd() end)

    refute minute_changed =~
             ~r/elmc_fn_Main_RequestWeather\(call_args_\d+, 1\);\s*elmc_release\(tmp_\d+\);\s*owned\[\d+\] = elmc_fn_Companion_Watch_sendWatchToPhone/

    refute minute_changed =~
             ~r/ElmcValue \*tmp_(\d+) = elmc_fn_Main_CurrentLocation[\s\S]*ElmcValue \*tmp_\1 = elmc_fn_Main_RequestWeather/

    assert minute_changed =~ "elmc_fn_Companion_Watch_sendWatchToPhone"
    assert minute_changed =~ "elmc_fn_Main_RequestWeather"
    assert minute_changed =~ "elmc_fn_Main_CurrentLocation"
  end
end
