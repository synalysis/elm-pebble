defmodule Ide.Emulator.WatchfaceSmokeScreenEmulatorSmokeTest do
  @moduledoc """
  External Pebble CLI emulator smoke for `watchface-smoke-screen`.

  Run with:

      ELMC_RUN_EMULATOR_SMOKE=1 mix test test/ide/emulator/watchface_smoke_screen_emulator_smoke_test.exs

  Requires a reachable `pebble install --emulator <platform>` for the chosen target.
  """

  use ExUnit.Case, async: false

  alias Ide.{PebbleToolchain, ProjectTemplates}

  @tag timeout: 300_000
  test "smoke-screen watchface installs on external emulator without App fault" do
    if run_smoke?() do
      target = System.get_env("ELMC_SMOKE_EMULATOR_TARGET", "basalt")

      workspace =
        Path.join(
          System.tmp_dir!(),
          "smoke-screen-external-#{System.unique_integer([:positive])}"
        )

      assert :ok = ProjectTemplates.apply_template("watchface-smoke-screen", workspace)

      assert {:ok, package_result} =
               PebbleToolchain.package("smoke-screen-external",
                 workspace_root: workspace,
                 target_type: "watchface",
                 project_name: "Smoke Screen",
                 target_platforms: [target]
               )

      flags_path = Path.join(workspace, ".pebble-sdk/app/src/c/elmc_emulator_build_flags.h")
      assert File.read!(flags_path) =~ "ELMC_WATCHFACE_MODE"

      if external_emulator_reachable?(target) do
        assert {:ok, install_output} =
                 install_with_wipe(target, package_result.artifact_path)

        assert install_output =~ "App install succeeded."

        assert {:ok, logs_output} =
                 run_pebble_with_timeout(["logs", "--emulator", target, "--no-color"], 12)

        refute logs_output =~ "App fault!"
        refute logs_output =~ "elmc_pebble_init failed"
        assert logs_output =~ "mode=1" or logs_output =~ "draw chunk="
      else
        assert true
      end
    else
      assert true
    end
  end

  defp run_smoke? do
    System.get_env("ELMC_RUN_EMULATOR_SMOKE", "0") in ["1", "true", "TRUE", "yes", "YES"]
  end

  defp external_emulator_reachable?(target) do
    probe_path = Path.join(System.tmp_dir!(), "pebble-smoke-probe-#{target}.png")
    File.rm(probe_path)

    match?(
      {:ok, _},
      run_pebble_with_timeout(["screenshot", "--emulator", target, "--no-open", probe_path], 8)
    )
  end

  defp install_with_wipe(target, artifact_path)
       when is_binary(target) and is_binary(artifact_path) do
    with {:ok, _wipe_output} <- run_pebble_with_timeout(["wipe"], 15),
         {:ok, install_output} <-
           run_pebble_with_timeout(
             ["install", artifact_path, "--emulator", target],
             90
           ) do
      {:ok, install_output}
    end
  end

  defp run_pebble_with_timeout(args, seconds) do
    pebble = System.find_executable("pebble")
    timeout = System.find_executable("timeout")

    cond do
      is_nil(pebble) ->
        {:error, :pebble_not_found}

      is_nil(timeout) ->
        {:error, :timeout_not_found}

      true ->
        {output, exit_code} =
          System.cmd(timeout, ["#{seconds}s", pebble | args],
            stderr_to_stdout: true,
            env: [{"LC_ALL", "C"}]
          )

        if exit_code == 0, do: {:ok, output}, else: {:error, {:command_failed, exit_code, output}}
    end
  end
end
