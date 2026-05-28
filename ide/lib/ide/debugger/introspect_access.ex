defmodule Ide.Debugger.IntrospectAccess do
  @moduledoc false

  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.CmdCall

  @spec list(Types.elm_introspect() | nil, String.t()) :: Types.param_list()
  def list(ei, key) when is_map(ei) and is_binary(key) do
    case Map.get(ei, key) do
      xs when is_list(xs) ->
        xs
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()

      _ ->
        []
    end
  end

  def list(_ei, _key), do: []

  @spec cmd_calls(Types.elm_introspect() | nil, String.t()) :: [Types.cmd_call()]
  def cmd_calls(ei, key) when is_map(ei) and is_binary(key) do
    case Map.get(ei, key) do
      rows when is_list(rows) ->
        rows
        |> Enum.filter(&is_map/1)
        |> Enum.map(&normalize_cmd_call_row/1)
        |> Enum.filter(fn row -> is_binary(row["name"]) and row["name"] != "" end)

      _ ->
        []
    end
  end

  def cmd_calls(_ei, _key), do: []

  @spec normalize_cmd_call_row(Types.cmd_call() | CmdCall.wire_map()) :: CmdCall.wire_map()
  defp normalize_cmd_call_row(row) when is_map(row) do
    base = %{
      "target" => Map.get(row, "target") || Map.get(row, :target),
      "name" => Map.get(row, "name") || Map.get(row, :name),
      "callback_constructor" =>
        Map.get(row, "callback_constructor") || Map.get(row, :callback_constructor),
      "branch" => Map.get(row, "branch") || Map.get(row, :branch),
      "branch_constructor" => Map.get(row, "branch_constructor") || Map.get(row, :branch_constructor),
      "event_kind" => Map.get(row, "event_kind") || Map.get(row, :event_kind),
      "label" => Map.get(row, "label") || Map.get(row, :label),
      "arg_snippets" => Map.get(row, "arg_snippets") || Map.get(row, :arg_snippets) || [],
      "arg_values" => Map.get(row, "arg_values") || Map.get(row, :arg_values) || [],
      "arg_kinds" => Map.get(row, "arg_kinds") || Map.get(row, :arg_kinds) || []
    }

    case Map.get(row, "activation_guards") || Map.get(row, :activation_guards) do
      guards when is_list(guards) and guards != [] ->
        Map.put(base, "activation_guards", guards)

      _ ->
        base
    end
  end
end
