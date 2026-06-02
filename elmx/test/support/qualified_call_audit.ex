defmodule Elmx.TestSupport.QualifiedCallAudit do
  @moduledoc false

  @fallback_patterns [
    ~r/Elmx\.Runtime\.Stdlib\.qualified_call\(/,
    ~r/raise "unsupported internal call/,
    ~r/raise "unsupported elmx runtime call/
  ]

  @doc """
  Scans generated Elixir module sources for runtime stdlib fallbacks that may raise at runtime.
  """
  @spec scan_sources([String.t()]) :: [map()]
  def scan_sources(sources) when is_list(sources) do
    sources
    |> Enum.flat_map(&scan_source/1)
    |> Enum.uniq()
  end

  @spec scan_compile_result(Elmx.CompileResult.t()) :: [map()]
  def scan_compile_result(%Elmx.CompileResult{modules: modules}) do
    modules
    |> Enum.map(& &1.source)
    |> scan_sources()
  end

  defp scan_source(source) when is_binary(source) do
    lines = String.split(source, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      @fallback_patterns
      |> Enum.filter(&Regex.match?(&1, line))
      |> Enum.map(fn pattern ->
        %{
          pattern: pattern.source,
          line: line_no,
          excerpt: String.trim(line)
        }
      end)
    end)
  end
end
