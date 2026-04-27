defmodule Ide.PebbleSurfaceEmulatorSmokeTest do
  use ExUnit.Case

  alias Ide.PebbleToolchain

  @fixture_workspace Path.expand("../../elmc/test/fixtures/pebble_surface_project", __DIR__)

  @tag timeout: 240_000
  test "surface fixture installs on emulator and runs without faults" do
    if run_smoke?() do
      assert System.find_executable("pebble"),
             "pebble CLI not found; cannot run emulator smoke test"

      target = System.get_env("ELMC_SMOKE_EMULATOR_TARGET", "chalk")

      assert {:ok, package_result} =
               PebbleToolchain.package("pebble-surface-smoke",
                 workspace_root: @fixture_workspace,
                 target_type: "app",
                 project_name: "Pebble Surface Smoke",
                 target_platforms: [target]
               )

      if emulator_reachable?(target) do
        assert {:ok, install_output} =
                 install_with_wipe(target, package_result.artifact_path)

        assert String.contains?(install_output, "App install succeeded.")

        assert {:ok, logs_output} =
                 run_pebble_with_timeout(["logs", "--emulator", target, "--no-color"], 8)

        assert String.contains?(logs_output, "cmd current_time=")
        refute String.contains?(logs_output, "App fault!")

        model_values =
          Regex.scan(~r/model=(-?\d+)/, logs_output, capture: :all_but_first)
          |> List.flatten()
          |> Enum.map(&String.to_integer/1)

        assert model_values != []
        assert Enum.any?(model_values, &(&1 != 0))

        screenshot_path = Path.join(System.tmp_dir!(), "pebble-surface-smoke-#{target}.png")
        File.rm(screenshot_path)

        Process.sleep(1500)

        assert {:ok, screenshot_output} =
                 run_pebble_with_timeout(
                   ["screenshot", "--emulator", target, "--no-open", screenshot_path],
                   20
                 )

        assert String.contains?(screenshot_output, "Saved screenshot")
        assert File.exists?(screenshot_path)
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

  defp emulator_reachable?(target) do
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
           run_pebble_with_timeout(["install", "--emulator", target, artifact_path], 45) do
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

        if exit_code == 0 do
          {:ok, output}
        else
          {:error, {:command_failed, exit_code, output}}
        end
    end
  end
end
