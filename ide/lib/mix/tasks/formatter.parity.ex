defmodule Mix.Tasks.Formatter.Parity do
  @shortdoc "Compare Ide.Formatter against elm-format fixtures"
  @moduledoc """
  Runs the formatter parity harness against elm-format fixture files.

      mix formatter.parity
      mix formatter.parity --limit 25
      mix formatter.parity --fixtures /path/to/test-files/good
      mix formatter.parity --reference elm-format
      mix formatter.parity --json-output tmp/parity.json
      mix formatter.parity --mismatch-log tmp/parity-mismatches.jsonl
      mix formatter.parity --baseline tmp/parity-baseline.json
      mix formatter.parity --baseline tmp/parity-baseline.json --update-baseline
      mix formatter.parity --phase A --baseline tmp/parity-baseline.json
      mix formatter.parity --shard-total 4 --shard-index 0
  """

  use Mix.Task

  alias Ide.Formatter.Parity

  @switches [
    limit: :integer,
    fixtures: :string,
    reference: :string,
    shard_total: :integer,
    shard_index: :integer,
    phase: :string,
    min_parity: :float,
    show_mismatches: :integer,
    mismatch_log: :string,
    json_output: :string,
    baseline: :string,
    update_baseline: :boolean
  ]

  @impl true
  @spec run(term()) :: term()
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} = OptionParser.parse(args, switches: @switches)

    harness_opts =
      [
        fixture_root: opts[:fixtures],
        limit: opts[:limit],
        reference_executable: opts[:reference],
        shard_total: opts[:shard_total],
        shard_index: opts[:shard_index]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case Parity.run(harness_opts) do
      {:ok, result} ->
        Mix.shell().info("fixture_root: #{result.fixture_root}")
        Mix.shell().info("total: #{result.total}")
        Mix.shell().info("comparable_total: #{result.comparable_total}")
        Mix.shell().info("match: #{result.match}")
        Mix.shell().info("mismatch: #{result.mismatch}")
        Mix.shell().info("formatter_error: #{result.formatter_error}")
        Mix.shell().info("reference_error: #{result.reference_error}")
        Mix.shell().info("known_limitations: #{result.known_limitations}")
        Mix.shell().info("unexpected_formatter_error: #{result.unexpected_formatter_error}")
        Mix.shell().info("unexpected_reference_error: #{result.unexpected_reference_error}")
        Mix.shell().info("actionable_total: #{result.actionable_total}")
        Mix.shell().info("actionable_match: #{result.actionable_match}")
        Mix.shell().info("actionable_parity_pct: #{Float.round(result.actionable_parity_pct, 3)}")
        Mix.shell().info("parity_pct: #{Float.round(result.parity_pct, 3)}")
        Mix.shell().info("comparable_parity_pct: #{Float.round(result.comparable_parity_pct, 3)}")
        Mix.shell().info("category_counts: #{inspect(result.category_counts)}")

        show_limit = opts[:show_mismatches] || 20

        result.results
        |> Enum.filter(&(&1.status != :match))
        |> Enum.take(show_limit)
        |> Enum.each(fn item ->
          Mix.shell().info("\n[#{item.status}] #{item.fixture}")

          if item.known_limitation? and is_binary(item.limitation_reason) do
            Mix.shell().info("[known limitation] #{item.limitation_reason}")
          end

          if item.message, do: Mix.shell().info(item.message)
        end)

        maybe_write_json_output(result, opts[:json_output])
        maybe_write_mismatch_log(result, opts[:mismatch_log])
        maybe_handle_baseline(result, opts)
        maybe_enforce_phase_gate(result, opts)

      {:error, reason} ->
        Mix.raise(format_error(reason))
    end
  end

  @spec format_error(term()) :: String.t()
  defp format_error(:missing_fixture_root) do
    "formatter parity requires --fixtures PATH or ELM_FORMAT_FIXTURES_ROOT"
  end

  defp format_error(reason), do: "formatter parity failed: #{inspect(reason)}"

  @spec maybe_write_json_output(term(), term()) :: term()
  defp maybe_write_json_output(_result, nil), do: :ok

  defp maybe_write_json_output(result, output_path) do
    payload =
      result
      |> Map.put(:generated_at, DateTime.utc_now() |> DateTime.to_iso8601())

    json = Jason.encode!(payload, pretty: true)
    parent = Path.dirname(output_path)
    File.mkdir_p!(parent)
    File.write!(output_path, json <> "\n")
    Mix.shell().info("json_report: #{output_path}")
  end

  @spec maybe_write_mismatch_log(term(), term()) :: term()
  defp maybe_write_mismatch_log(_result, nil), do: :ok

  defp maybe_write_mismatch_log(result, output_path) do
    rows =
      result.results
      |> Enum.filter(&(&1.status != :match))
      |> Enum.map(fn item ->
        Jason.encode!(%{
          fixture: item.fixture,
          status: item.status,
          category: item.category,
          known_limitation?: item.known_limitation?,
          limitation_reason: item.limitation_reason,
          message: item.message,
          diff: item.diff
        })
      end)
      |> Enum.join("\n")

    parent = Path.dirname(output_path)
    File.mkdir_p!(parent)
    payload = if rows == "", do: "", else: rows <> "\n"
    File.write!(output_path, payload)
    Mix.shell().info("mismatch_log: #{output_path}")
  end

  @spec maybe_handle_baseline(term(), term()) :: term()
  defp maybe_handle_baseline(result, opts) do
    baseline_path = opts[:baseline]
    update? = opts[:update_baseline] || false

    cond do
      is_nil(baseline_path) ->
        :ok

      update? ->
        write_baseline!(baseline_path, result)
        Mix.shell().info("baseline_updated: #{baseline_path}")

      true ->
        baseline = read_baseline!(baseline_path)
        expected_actionable_match = baseline_target_match(baseline)

        if result.actionable_match < expected_actionable_match do
          Mix.raise(
            "parity regression detected: actionable_match=#{result.actionable_match} is below baseline=#{expected_actionable_match} (#{baseline_path})"
          )
        else
          Mix.shell().info(
            "baseline_check: ok (actionable_match #{result.actionable_match} >= #{expected_actionable_match})"
          )
        end
    end
  end

  @spec maybe_enforce_phase_gate(term(), term()) :: term()
  defp maybe_enforce_phase_gate(result, opts) do
    phase = opts[:phase] && String.upcase(opts[:phase])
    min_parity = opts[:min_parity] || phase_threshold(phase)

    case phase_gate_outcome(result, min_parity) do
      :disabled ->
        :ok

      :empty ->
        Mix.raise("cannot evaluate parity gate with zero fixtures")

      :skipped ->
        Mix.shell().info("parity_gate: skipped (no actionable fixtures in selection)")

      :failed ->
        Mix.raise(
          "parity gate failed: actionable_parity_pct=#{Float.round(result.actionable_parity_pct, 3)} below threshold=#{min_parity}"
        )

      :passed ->
        Mix.shell().info(
          "parity_gate: ok (#{Float.round(result.actionable_parity_pct, 3)} >= #{min_parity})"
        )
    end
  end

  @doc false
  @spec phase_gate_outcome(term(), term()) :: term()
  def phase_gate_outcome(result, min_parity) when is_map(result) do
    cond do
      is_nil(min_parity) ->
        :disabled

      result.total == 0 ->
        :empty

      result.actionable_total == 0 ->
        :skipped

      result.actionable_parity_pct < min_parity ->
        :failed

      true ->
        :passed
    end
  end

  @doc false
  @spec baseline_target_match(term()) :: term()
  def baseline_target_match(baseline) when is_map(baseline) do
    baseline["actionable_match"] || baseline["match"] || 0
  end

  @spec phase_threshold(term()) :: term()
  defp phase_threshold(nil), do: nil
  defp phase_threshold("A"), do: 95.0
  defp phase_threshold("B"), do: 98.0
  defp phase_threshold("C"), do: 100.0
  defp phase_threshold(_), do: nil

  @spec write_baseline!(term(), term()) :: term()
  defp write_baseline!(path, result) do
    payload = %{
      fixture_root: result.fixture_root,
      match: result.match,
      actionable_match: result.actionable_match,
      known_limitations: result.known_limitations,
      total: result.total,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    json = Jason.encode!(payload, pretty: true)
    parent = Path.dirname(path)
    File.mkdir_p!(parent)
    File.write!(path, json <> "\n")
  end

  @spec read_baseline!(term()) :: term()
  defp read_baseline!(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, payload} when is_map(payload) -> payload
          {:ok, _} -> Mix.raise("invalid baseline format at #{path}")
          {:error, reason} -> Mix.raise("invalid baseline json at #{path}: #{inspect(reason)}")
        end

      {:error, reason} ->
        Mix.raise("failed to read baseline #{path}: #{inspect(reason)}")
    end
  end
end
