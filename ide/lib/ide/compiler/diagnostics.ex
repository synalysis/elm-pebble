defmodule Ide.Compiler.Diagnostics do
  @moduledoc """
  Shared diagnostic normalization and count helpers.
  """

  @type diagnostic_map :: map()
  @type summary :: %{
          error_count: non_neg_integer(),
          warning_count: non_neg_integer(),
          info_count: non_neg_integer()
        }

  @spec normalize_list(term()) :: [diagnostic_map()]
  def normalize_list(value) when is_list(value) do
    value
    |> Enum.filter(&is_map/1)
    |> Enum.map(&normalize_diagnostic/1)
  end

  def normalize_list(_), do: []

  @spec summary(term()) :: summary()
  def summary(diagnostics) do
    diagnostics
    |> normalize_list()
    |> Enum.reduce(%{error_count: 0, warning_count: 0, info_count: 0}, fn diagnostic, acc ->
      case Map.get(diagnostic, :severity) do
        "error" -> %{acc | error_count: acc.error_count + 1}
        "warning" -> %{acc | warning_count: acc.warning_count + 1}
        _ -> %{acc | info_count: acc.info_count + 1}
      end
    end)
  end

  @spec normalize_diagnostic(map()) :: diagnostic_map()
  def normalize_diagnostic(diagnostic) when is_map(diagnostic) do
    severity =
      diagnostic
      |> value(:severity, "info")
      |> to_string()
      |> String.downcase()

    %{
      severity: severity,
      message: diagnostic |> value(:message, "") |> to_string(),
      source: diagnostic |> value(:source, "elmc") |> to_string(),
      file: value(diagnostic, :file),
      line: normalize_integer(value(diagnostic, :line)),
      column: normalize_integer(value(diagnostic, :column)),
      warning_type: value(diagnostic, :warning_type),
      warning_code: value(diagnostic, :warning_code),
      warning_constructor: value(diagnostic, :warning_constructor),
      warning_expected_kind: value(diagnostic, :warning_expected_kind),
      warning_has_arg_pattern: value(diagnostic, :warning_has_arg_pattern)
    }
  end

  @spec value(term(), term(), term()) :: term()
  defp value(map, key, default \\ nil) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, Atom.to_string(key)) -> Map.get(map, Atom.to_string(key))
      true -> default
    end
  end

  @spec normalize_integer(term()) :: term()
  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp normalize_integer(_), do: nil
end
