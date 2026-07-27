defmodule Elmc.Diagnostics do
  @moduledoc false

  alias Elmc.Types

  @type cli_diagnostic :: Types.cli_diagnostic()

  @spec severity(cli_diagnostic() | String.t() | atom()) :: String.t()
  def severity(diagnostic) when is_map(diagnostic) do
    diagnostic
    |> Map.get("severity", Map.get(diagnostic, :severity, "warning"))
    |> severity()
  end

  def severity(value) when is_atom(value), do: value |> Atom.to_string() |> severity()
  def severity(value) when is_binary(value), do: String.downcase(value)
  def severity(_value), do: "warning"

  @spec error?(cli_diagnostic()) :: boolean()
  def error?(diagnostic) when is_map(diagnostic), do: severity(diagnostic) == "error"

  @spec errors_only([cli_diagnostic()]) :: [cli_diagnostic()]
  def errors_only(diagnostics) when is_list(diagnostics) do
    Enum.filter(diagnostics, &error?/1)
  end

  @spec partition([cli_diagnostic()]) :: {[cli_diagnostic()], [cli_diagnostic()]}
  def partition(diagnostics) when is_list(diagnostics) do
    Enum.split_with(diagnostics, &error?/1)
  end

  @spec blocking_from_sources([{atom(), [cli_diagnostic()]}]) :: [cli_diagnostic()]
  def blocking_from_sources(sources) when is_list(sources) do
    sources
    |> Enum.flat_map(fn {_key, diagnostics} -> diagnostics end)
    |> errors_only()
  end
end
