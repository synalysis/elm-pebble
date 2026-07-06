defmodule Ide.GameElmtrisElmxElmcParityTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Ide.Test.TemplateElmxElmcParity, as: Parity
  alias Ide.Test.TemplateElmxElmcParity.Compare
  alias Ide.Test.TemplateElmxElmcParity.ElmcRunner
  alias Ide.Test.TemplateElmxElmcParity.ElmxRunner
  alias Ide.Test.TemplateElmxElmcParity.ExecutionPlan

  @template_key "game-elmtris"

  setup do
    on_exit(fn -> Parity.release!(@template_key) end)
    :ok
  end

  @tag timeout: 300_000
  test "elmx and elmc agree after repeated Down button presses on fresh Elmtris game" do
    if is_nil(System.find_executable("cc")) do
      IO.puts("Skipping Elmtris down-button parity (cc not available)")
      assert true
    else
      assert {:ok, prepared} = Parity.prepare!(@template_key)

      plan =
        prepared.project_dir
        |> ExecutionPlan.game_elmtris_down_button_scenario!(down_presses: 8)
        |> ExecutionPlan.for_watch_profile("basalt")

      prepared = %{prepared | plan: plan}

      assert {:ok, elmx_steps} = ElmxRunner.run!(plan, prepared: prepared)
      assert_no_backend_errors!(elmx_steps, "elmx")
      assert_valid_elmtris_model_after_down!(elmx_steps, "elmx")

      case ElmcRunner.run!(plan, prepared: prepared) do
        {:ok, elmc_steps} ->
          assert_no_backend_errors!(elmc_steps, "elmc")
          assert_valid_elmtris_model_after_down!(elmc_steps, "elmc")

          mismatches = Compare.diff(elmx_steps, elmc_steps)

          assert mismatches == [],
                 Compare.format_report(@template_key, "basalt", mismatches)

        {:error, {:harness_run_failed, exit_code, output}} ->
          flunk("""
          elmc host harness crashed during Down button scenario (exit #{exit_code}).

          This matches the emulator-only Elmtris Down-button fault: elmx completes the
          same DownPressed steps, but elmc segfaults while handling softDrop.

          Last harness output:
          #{String.slice(output, max(byte_size(output) - 4000, 0), 4000)}
          """)

        {:error, reason} ->
          flunk("elmc Down button scenario failed: #{inspect(reason)}")
      end
    end
  end

  defp assert_no_backend_errors!(steps, backend) when is_list(steps) and is_binary(backend) do
    failures =
      steps
      |> Enum.filter(fn step ->
        error = Map.get(step, "error")
        error not in [nil, ""]
      end)

    assert failures == [],
           "#{backend} reported errors during Down button scenario:\n#{format_step_errors(failures)}"
  end

  defp assert_valid_elmtris_model_after_down!(steps, backend) do
    step =
      steps
      |> Enum.find(fn step ->
        step["op"] == "update" and step["step_id"] == "update:DownPressed:1"
      end)

    assert step, "expected update:DownPressed:1 step for #{backend}"

    model = Map.get(step, "model")

    refute model in [nil, "", "0"],
           "#{backend} model corrupted after first Down press: #{inspect(model)}"
  end

  defp format_step_errors(steps) do
    steps
    |> Enum.map(fn step ->
      "  #{step["step_id"]} (#{step["backend"]}): #{inspect(step["error"])}"
    end)
    |> Enum.join("\n")
  end
end
