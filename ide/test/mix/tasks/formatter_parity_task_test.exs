defmodule Mix.Tasks.Formatter.ParityTaskTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Formatter.Parity, as: ParityTask

  test "phase gate outcome is disabled without threshold" do
    result = %{total: 10, actionable_total: 10, actionable_parity_pct: 100.0}
    assert ParityTask.phase_gate_outcome(result, nil) == :disabled
  end

  test "phase gate outcome is empty with zero fixtures" do
    result = %{total: 0, actionable_total: 0, actionable_parity_pct: 0.0}
    assert ParityTask.phase_gate_outcome(result, 100.0) == :empty
  end

  test "phase gate outcome is skipped with no actionable fixtures" do
    result = %{total: 4, actionable_total: 0, actionable_parity_pct: 0.0}
    assert ParityTask.phase_gate_outcome(result, 100.0) == :skipped
  end

  test "phase gate outcome is failed below threshold" do
    result = %{total: 10, actionable_total: 8, actionable_parity_pct: 99.0}
    assert ParityTask.phase_gate_outcome(result, 100.0) == :failed
  end

  test "phase gate outcome is passed at threshold" do
    result = %{total: 10, actionable_total: 8, actionable_parity_pct: 100.0}
    assert ParityTask.phase_gate_outcome(result, 100.0) == :passed
  end

  test "baseline target match prefers actionable_match" do
    baseline = %{"match" => 10, "actionable_match" => 7}
    assert ParityTask.baseline_target_match(baseline) == 7
  end

  test "baseline target match falls back to legacy match" do
    baseline = %{"match" => 12}
    assert ParityTask.baseline_target_match(baseline) == 12
  end

  test "baseline update writes actionable fields" do
    root =
      Path.join(System.tmp_dir!(), "ide_parity_baseline_#{System.unique_integer([:positive])}")

    fixture = Path.join(root, "Main.elm")
    baseline_path = Path.join(root, "parity-baseline.json")
    File.mkdir_p!(root)
    File.write!(fixture, "module Main exposing (main)\n\nmain = 1\n")
    on_exit(fn -> File.rm_rf(root) end)

    with_process_shell(fn ->
      ParityTask.run(["--fixtures", root, "--baseline", baseline_path, "--update-baseline"])
    end)

    {:ok, content} = File.read(baseline_path)
    {:ok, payload} = Jason.decode(content)
    assert is_integer(payload["match"])
    assert is_integer(payload["actionable_match"])
    assert is_integer(payload["known_limitations"])
  end

  test "mismatch log includes known limitation metadata" do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_parity_mismatch_log_#{System.unique_integer([:positive])}"
      )

    fixture = Path.join(root, "Elm-0.17/AllSyntax/LineComments/Module.elm")
    mismatch_log = Path.join(root, "parity-mismatches.jsonl")
    File.mkdir_p!(Path.dirname(fixture))
    File.write!(fixture, "value = @\n")
    on_exit(fn -> File.rm_rf(root) end)

    with_process_shell(fn ->
      ParityTask.run(["--fixtures", root, "--mismatch-log", mismatch_log])
    end)

    {:ok, content} = File.read(mismatch_log)
    [line | _] = String.split(content, "\n", trim: true)
    {:ok, payload} = Jason.decode(line)

    assert payload["status"] == "formatter_error"
    assert payload["known_limitation?"] == true
    assert is_binary(payload["limitation_reason"])
  end

  test "task prints skipped gate message when selection has only known limitations" do
    root =
      Path.join(System.tmp_dir!(), "ide_parity_known_only_#{System.unique_integer([:positive])}")

    fixture = Path.join(root, "Elm-0.17/AllSyntax/LineComments/Module.elm")
    File.mkdir_p!(Path.dirname(fixture))
    File.write!(fixture, "value = @\n")
    on_exit(fn -> File.rm_rf(root) end)

    with_process_shell(fn ->
      ParityTask.run(["--fixtures", root, "--phase", "C", "--show-mismatches", "1"])
    end)

    assert shell_output_contains?("parity_gate: skipped (no actionable fixtures in selection)")
  end

  defp shell_output_contains?(needle, attempts \\ 40)

  defp shell_output_contains?(_needle, 0), do: false

  defp shell_output_contains?(needle, attempts) do
    receive do
      {:mix_shell, :info, [message]} ->
        String.contains?(message, needle) or shell_output_contains?(needle, attempts - 1)
    after
      25 ->
        false
    end
  end

  defp with_process_shell(fun) when is_function(fun, 0) do
    old_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    try do
      fun.()
    after
      Mix.shell(old_shell)
    end
  end
end
