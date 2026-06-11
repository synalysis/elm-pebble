defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Util.Elm do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type runtime_value :: Types.runtime_value()

  @spec value(runtime_value()) :: String.t()
  def value(%{} = map) do
    ctor = Map.get(map, "ctor") || Map.get(map, "$ctor")
    args = Map.get(map, "args") || Map.get(map, "$args") || []

    cond do
      is_binary(ctor) and args == [] ->
        ctor

      is_binary(ctor) and is_list(args) ->
        ([ctor] ++ Enum.map(args, &value/1)) |> Enum.join(" ")

      true ->
        fields =
          map
          |> Enum.reject(fn {key, _field_value} -> key in ["ctor", "args", "$ctor", "$args"] end)
          |> Enum.sort_by(fn {key, _field_value} -> key end)
          |> Enum.map(fn {key, field_value} ->
            "#{field_name(key)} = #{value(field_value)}"
          end)
          |> Enum.join(", ")

        "{ #{fields} }"
    end
  end

  def value(values) when is_list(values) do
    "[" <> Enum.map_join(values, ", ", &value/1) <> "]"
  end

  def value(value) when is_binary(value), do: inspect(value)
  def value(true), do: "True"
  def value(false), do: "False"
  def value(nil), do: "null"
  def value(value), do: to_string(value)

  @spec field_name(atom() | String.t() | integer()) :: String.t()
  def field_name(key) when is_binary(key), do: key
  def field_name(key), do: to_string(key)
end
