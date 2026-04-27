defmodule Ide.Formatter.Parity do
  @moduledoc """
  Compatibility harness for comparing `Ide.Formatter` output against `elm-format`.
  """

  alias Ide.Formatter

  @default_reference_executable "elm-format"

  @type case_result :: %{
          fixture: String.t(),
          status: :match | :mismatch | :formatter_error | :reference_error,
          category: atom() | nil,
          diff: map() | nil,
          message: String.t() | nil,
          known_limitation?: boolean(),
          limitation_reason: String.t() | nil
        }

  @type run_result :: %{
          fixture_root: String.t(),
          total: non_neg_integer(),
          comparable_total: non_neg_integer(),
          match: non_neg_integer(),
          mismatch: non_neg_integer(),
          formatter_error: non_neg_integer(),
          reference_error: non_neg_integer(),
          known_limitations: non_neg_integer(),
          unexpected_formatter_error: non_neg_integer(),
          unexpected_reference_error: non_neg_integer(),
          actionable_total: non_neg_integer(),
          actionable_match: non_neg_integer(),
          actionable_parity_pct: float(),
          parity_pct: float(),
          comparable_parity_pct: float(),
          category_counts: map(),
          results: [case_result()]
        }

  @spec run(keyword()) :: {:ok, run_result()} | {:error, term()}
  def run(opts \\ []) do
    fixture_root = Keyword.get(opts, :fixture_root, default_fixture_root())
    limit = Keyword.get(opts, :limit, nil)
    reference_executable = Keyword.get(opts, :reference_executable, @default_reference_executable)
    shard_total = Keyword.get(opts, :shard_total, nil)
    shard_index = Keyword.get(opts, :shard_index, nil)

    with :ok <- ensure_fixture_root(fixture_root),
         {:ok, fixtures} <- discover_fixtures(fixture_root) do
      selected =
        fixtures
        |> maybe_apply_shard(shard_total, shard_index)
        |> maybe_take(limit)

      results =
        Enum.map(selected, fn fixture ->
          compare_fixture(fixture, fixture_root, reference_executable)
        end)

      {:ok, summarize(fixture_root, results)}
    end
  end

  @spec discover_fixtures(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def discover_fixtures(fixture_root) do
    do_discover_fixtures(fixture_root)
  end

  @spec do_discover_fixtures(term()) :: term()
  defp do_discover_fixtures(root) do
    case File.ls(root) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.reduce([], fn entry, acc ->
          full_path = Path.join(root, entry)

          cond do
            File.dir?(full_path) ->
              case do_discover_fixtures(full_path) do
                {:ok, nested} -> acc ++ nested
                {:error, _} -> acc
              end

            String.ends_with?(entry, ".elm") ->
              acc ++ [full_path]

            true ->
              acc
          end
        end)
        |> then(&{:ok, &1})

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec compare_fixture(term(), term(), term()) :: term()
  defp compare_fixture(path, fixture_root, reference_executable) do
    rel = Path.relative_to(path, fixture_root)

    with {:ok, source} <- File.read(path),
         {:ok, ide_result} <- Formatter.format(source),
         {:ok, reference_output} <- run_reference_formatter(source, reference_executable) do
      ide_output = normalize_output(ide_result.formatted_source)
      ref_output = normalize_output(reference_output)

      if ide_output == ref_output do
        %{
          fixture: rel,
          status: :match,
          category: nil,
          diff: nil,
          message: nil,
          known_limitation?: false,
          limitation_reason: nil
        }
      else
        diff = diff_details(ide_output, ref_output)

        %{
          fixture: rel,
          status: :mismatch,
          category: categorize_mismatch(ide_output, ref_output),
          diff: diff,
          message: diff_message(diff),
          known_limitation?: false,
          limitation_reason: nil
        }
      end
    else
      {:error, %{source: source, message: message}} when is_binary(source) ->
        build_error_result(rel, :formatter_error, "[#{source}] #{message}")

      {:error, {:reference_failed, message}} ->
        build_error_result(rel, :reference_error, message)

      {:error, reason} ->
        build_error_result(rel, :formatter_error, inspect(reason))
    end
  end

  @spec build_error_result(term(), term(), term()) :: term()
  defp build_error_result(rel, status, message) do
    {known?, reason} = known_limitation(rel, status)

    %{
      fixture: rel,
      status: status,
      category: if(known?, do: :known_limitation, else: status),
      diff: nil,
      message: message,
      known_limitation?: known?,
      limitation_reason: reason
    }
  end

  @spec run_reference_formatter(term(), term()) :: term()
  defp run_reference_formatter(source, executable) do
    temp_dir = System.tmp_dir!()

    temp_path =
      Path.join(temp_dir, "ide_formatter_parity_#{System.unique_integer([:positive])}.elm")

    result =
      try do
        with :ok <- File.write(temp_path, source) do
          {output, exit_code} =
            System.cmd(executable, [temp_path, "--output", "/dev/stdout", "--yes"])

          if exit_code == 0 do
            {:ok, output}
          else
            {:error, {:reference_failed, output}}
          end
        else
          {:error, reason} ->
            {:error, {:reference_failed, inspect(reason)}}
        end
      rescue
        error ->
          {:error, {:reference_failed, inspect(error)}}
      end

    File.rm(temp_path)
    result
  end

  @spec ensure_fixture_root(term()) :: term()
  defp ensure_fixture_root(nil), do: {:error, :missing_fixture_root}

  defp ensure_fixture_root(path) do
    if File.dir?(path), do: :ok, else: {:error, {:missing_fixture_root, path}}
  end

  @spec maybe_take(term(), term()) :: term()
  defp maybe_take(values, nil), do: values

  defp maybe_take(values, limit) when is_integer(limit) and limit > 0 do
    Enum.take(values, limit)
  end

  defp maybe_take(values, _), do: values

  @spec maybe_apply_shard(term(), term(), term()) :: term()
  defp maybe_apply_shard(values, nil, _), do: values
  defp maybe_apply_shard(values, _, nil), do: values

  defp maybe_apply_shard(values, shard_total, shard_index)
       when is_integer(shard_total) and shard_total > 0 and is_integer(shard_index) and
              shard_index >= 0 do
    values
    |> Enum.with_index()
    |> Enum.filter(fn {_value, idx} -> rem(idx, shard_total) == shard_index end)
    |> Enum.map(fn {value, _idx} -> value end)
  end

  defp maybe_apply_shard(values, _shard_total, _shard_index), do: values

  @spec normalize_output(term()) :: term()
  defp normalize_output(output) do
    output
    |> String.replace(~r/^Processing file .*\n?/m, "")
    |> String.replace("\r\n", "\n")
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  @spec summarize(term(), term()) :: term()
  defp summarize(fixture_root, results) do
    counts = Enum.frequencies_by(results, & &1.status)

    category_counts =
      results
      |> Enum.map(& &1.category)
      |> Enum.filter(&(!is_nil(&1)))
      |> Enum.frequencies()

    total = length(results)
    match = Map.get(counts, :match, 0)
    parity_pct = if total == 0, do: 0.0, else: match * 100.0 / total
    reference_error = Map.get(counts, :reference_error, 0)
    known_limitations = Enum.count(results, & &1.known_limitation?)

    unexpected_formatter_error =
      Enum.count(results, fn item ->
        item.status == :formatter_error and not item.known_limitation?
      end)

    unexpected_reference_error =
      Enum.count(results, fn item ->
        item.status == :reference_error and not item.known_limitation?
      end)

    comparable_total = max(total - reference_error, 0)

    comparable_parity_pct =
      if comparable_total == 0, do: 0.0, else: match * 100.0 / comparable_total

    actionable_total = max(total - known_limitations, 0)
    actionable_match = match

    actionable_parity_pct =
      if actionable_total == 0, do: 0.0, else: actionable_match * 100.0 / actionable_total

    %{
      fixture_root: fixture_root,
      total: total,
      comparable_total: comparable_total,
      match: match,
      mismatch: Map.get(counts, :mismatch, 0),
      formatter_error: Map.get(counts, :formatter_error, 0),
      reference_error: reference_error,
      known_limitations: known_limitations,
      unexpected_formatter_error: unexpected_formatter_error,
      unexpected_reference_error: unexpected_reference_error,
      actionable_total: actionable_total,
      actionable_match: actionable_match,
      actionable_parity_pct: actionable_parity_pct,
      parity_pct: parity_pct,
      comparable_parity_pct: comparable_parity_pct,
      category_counts: category_counts,
      results: results
    }
  end

  @spec diff_message(term()) :: term()
  defp diff_message(%{
         line: line,
         column: column,
         actual: actual,
         expected: expected,
         actual_context: actual_context,
         expected_context: expected_context
       }) do
    """
    first mismatch at line #{line}, column #{column}
    actual:   #{inspect(actual)}
    expected: #{inspect(expected)}
    actual_context:
    #{actual_context}
    expected_context:
    #{expected_context}
    """
    |> String.trim()
  end

  @spec diff_details(term(), term()) :: term()
  defp diff_details(actual, expected) do
    actual_lines = String.split(actual, "\n", trim: false)
    expected_lines = String.split(expected, "\n", trim: false)
    max_len = max(length(actual_lines), length(expected_lines))

    mismatch_line_idx =
      if max_len == 0 do
        0
      else
        Enum.find(0..(max_len - 1), fn idx ->
          Enum.at(actual_lines, idx, "") != Enum.at(expected_lines, idx, "")
        end) || 0
      end

    actual_line = Enum.at(actual_lines, mismatch_line_idx, "")
    expected_line = Enum.at(expected_lines, mismatch_line_idx, "")
    col = first_diff_column(actual_line, expected_line)

    %{
      line: mismatch_line_idx + 1,
      column: col,
      actual: actual_line,
      expected: expected_line,
      actual_context: context_snippet(actual_lines, mismatch_line_idx),
      expected_context: context_snippet(expected_lines, mismatch_line_idx)
    }
  end

  @spec context_snippet(term(), term()) :: term()
  defp context_snippet(lines, mismatch_idx) do
    start_idx = max(mismatch_idx - 1, 0)
    end_idx = min(mismatch_idx + 1, length(lines) - 1)

    start_idx..end_idx
    |> Enum.map(fn idx ->
      marker = if idx == mismatch_idx, do: ">", else: " "
      "#{marker} #{idx + 1}: #{Enum.at(lines, idx, "")}"
    end)
    |> Enum.join("\n")
  end

  @spec first_diff_column(term(), term()) :: term()
  defp first_diff_column(actual_line, expected_line) do
    max_len = max(String.length(actual_line), String.length(expected_line))

    idx =
      Enum.find(0..max_len, fn i ->
        String.slice(actual_line, i, 1) != String.slice(expected_line, i, 1)
      end) || 0

    idx + 1
  end

  @spec categorize_mismatch(term(), term()) :: term()
  defp categorize_mismatch(actual, expected) do
    joined = actual <> "\n" <> expected

    cond do
      String.contains?(joined, "{") and String.contains?(joined, "}") and
          String.contains?(joined, ",") ->
        :record_layout

      String.contains?(joined, "case ") and String.contains?(joined, "->") ->
        :case_alignment

      String.contains?(joined, "import ") ->
        :imports

      String.contains?(joined, "--") or String.contains?(joined, "{-") ->
        :comments

      String.contains?(joined, "\\u{") or String.contains?(joined, "\\x") ->
        :unicode_escapes

      true ->
        :other
    end
  end

  @spec default_fixture_root() :: term()
  defp default_fixture_root do
    configured =
      Application.get_env(:ide, __MODULE__, [])
      |> Keyword.get(:fixtures_root)

    candidates =
      [
        configured,
        System.get_env("ELM_FORMAT_FIXTURES_ROOT")
      ]
      |> Enum.filter(&is_binary/1)

    Enum.find(candidates, &File.dir?/1) || List.first(candidates)
  end

  @spec known_limitation(term(), term()) :: term()
  defp known_limitation("Elm-0.17/AllSyntax/LineComments/Module.elm", :formatter_error),
    do: {true, "elm_ex parser limitation on Elm 0.17 line-comment header fixture"}

  defp known_limitation("Elm-0.17/AllSyntax/LineComments/ModuleEffect.elm", :formatter_error),
    do: {true, "elm_ex parser limitation on Elm 0.17 effect module line-comment fixture"}

  defp known_limitation("Elm-0.17/AllSyntax.elm", :reference_error),
    do: {true, "reference elm-format cannot parse this legacy fixture in current harness mode"}

  defp known_limitation("Elm-0.19/InfixAsVariableName.elm", :reference_error),
    do: {true, "reference elm-format parse failure for infix-as-variable fixture"}

  defp known_limitation(_fixture, _status), do: {false, nil}
end
