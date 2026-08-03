defmodule Elmc.TutorialCompleteMinuteCodegenTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Test.CCodegenExtract

  @moduletag timeout: 300_000
  @repo_root Path.expand("../..", __DIR__)
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
          Path.join(@repo_root, "packages/elm-pebble/elm-watch/src"),
          Path.join(@repo_root, "shared/elm"),
          Path.join(@repo_root, "ide/priv/internal_packages/companion-protocol/src"),
          Path.join(@repo_root, "ide/priv/bundled_elm/pebble-watch-src"),
          Path.join(@repo_root, "ide/priv/internal_packages/elm-time/src"),
          Path.join(@repo_root, "ide/priv/internal_packages/elm-random/src")
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
             CachedCompile.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               direct_render_only: false,
               plan_ir_mode: :primary,
               prune_runtime: false,
               prune_native_wrappers: true,
               pebble_int32: true,
               strip_dead_code: true
             })

    generated = File.read!(Path.join(out_dir, "c/elmc_generated.c"))

    minute_changed =
      generated
      |> CCodegenExtract.fn_body("elmc_fn_Main_update")
      |> String.split("elmc_plan_block_6:")
      |> Enum.at(1)
      |> String.split("elmc_plan_block_8:")
      |> hd()

    refute minute_changed =~
             ~r/elmc_fn_Main_RequestWeather\(call_args_\d+, 1\);\s*elmc_release\(tmp_\d+\);\s*owned\[\d+\] = elmc_fn_Companion_Watch_sendWatchToPhone/

    refute minute_changed =~
             ~r/ElmcValue \*tmp_(\d+) = elmc_fn_Main_CurrentLocation[\s\S]*ElmcValue \*tmp_\1 = elmc_fn_Main_RequestWeather/

    # Value-path send: tuple payload → elmc_cmd_companion_send_value (embeds COMPANION_SEND).
    assert minute_changed =~ "elmc_cmd_companion_send_value" or
             minute_changed =~ "ELMC_PEBBLE_CMD_COMPANION_SEND"

    assert minute_changed =~ "elmc_cmd_companion_send_value" or
             (minute_changed =~ "elmc_fn_Companion_Internal_watchToPhoneTag" and
                minute_changed =~ "elmc_fn_Companion_Internal_watchToPhoneValue")

    # RC ABI: `elmc_new_int(&owned[i], 1)` — legacy `_take` is gone.
    assert minute_changed =~ ~r/elmc_new_int(?:_take)?\((?:&owned\[\d+\],\s*)?1\)/
    assert minute_changed =~ ~r/elmc_tuple2\(&owned\[\d+\],\s*owned\[\d+\],\s*owned\[\d+\]\)/
  end
end
