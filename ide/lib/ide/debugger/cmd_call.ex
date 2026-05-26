defmodule Ide.Debugger.CmdCall do
  @moduledoc false

  @spec name?(map(), String.t()) :: boolean()
  def name?(row, name) when is_map(row) and is_binary(name),
    do: Map.get(row, "name") == name

  def name?(_row, _name), do: false

  @spec target_ends_with?(map(), String.t()) :: boolean()
  def target_ends_with?(row, suffix) when is_map(row) and is_binary(suffix) do
    case Map.get(row, "target") do
      target when is_binary(target) -> String.ends_with?(target, suffix)
      _ -> false
    end
  end

  def target_ends_with?(_row, _suffix), do: false

  @spec requests_current_position?(map(), map()) :: boolean()
  def requests_current_position?(ei, row) when is_map(ei) and is_map(row) do
    cond do
      name?(row, "currentPosition") or target_ends_with?(row, ".currentPosition") ->
        true

      true ->
        helper_name = Map.get(row, "target") || Map.get(row, "name")

        ei
        |> Map.get("function_cmd_calls", %{})
        |> case do
          helpers when is_map(helpers) -> Map.get(helpers, helper_name, [])
          _ -> []
        end
        |> Enum.any?(
          &(name?(&1, "currentPosition") or target_ends_with?(&1, ".currentPosition"))
        )
    end
  end

  def requests_current_position?(_ei, _row), do: false

  @spec subscription_call_matches?(map(), [String.t()]) :: boolean()
  def subscription_call_matches?(row, target_suffixes)
      when is_map(row) and is_list(target_suffixes) do
    Enum.any?(target_suffixes, &target_ends_with?(row, &1))
  end

  def subscription_call_matches?(_row, _target_suffixes), do: false

  @spec expand_helpers([map()], map()) :: [map()]
  def expand_helpers(calls, ei) when is_list(calls) and is_map(ei) do
    helpers =
      case Map.get(ei, "function_cmd_calls", %{}) do
        value when is_map(value) -> value
        _ -> %{}
      end

    Enum.flat_map(calls, fn row ->
      helper_name = Map.get(row, "target") || Map.get(row, "name")

      case Map.get(helpers, helper_name) do
        helper_calls when is_list(helper_calls) and helper_calls != [] -> helper_calls
        _ -> [row]
      end
    end)
  end

  def expand_helpers(calls, _ei) when is_list(calls), do: calls
end
