defmodule Ide.Debugger.EmulatorRcFailApply do
  @moduledoc false

  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.RuntimeSurfaceMerge
  alias Ide.Debugger.Types

  @spec apply(String.t(), map()) :: {:ok, Types.runtime_state()}
  def apply(project_slug, attrs) when is_binary(project_slug) and is_map(attrs) do
    code = parse_nonneg_int(Map.get(attrs, :code) || Map.get(attrs, "code"))
    line = parse_nonneg_int(Map.get(attrs, :line) || Map.get(attrs, "line"))

    AgentSession.mutate(project_slug, fn state ->
      if Map.get(state, :running, false) and is_integer(code) and code > 0 do
        fields =
          %{"elmc_last_fail_code" => code}
          |> maybe_put_line(line)
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        RuntimeSurfaceMerge.merge_into_state(state, :watch, fields)
      else
        state
      end
    end)
  end

  defp maybe_put_line(fields, line) when is_integer(line) and line > 0 do
    Map.put(fields, "elmc_last_fail_line", line)
  end

  defp maybe_put_line(fields, _), do: fields

  defp parse_nonneg_int(value) when is_integer(value) and value >= 0, do: value

  defp parse_nonneg_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n >= 0 -> n
      _ -> nil
    end
  end

  defp parse_nonneg_int(_), do: nil
end
