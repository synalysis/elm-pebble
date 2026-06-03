defmodule Elmx.Runtime.Core.Debug do
  @moduledoc false

  alias Elmx.Types

  require Logger

  @doc "Elm `Debug.log` — returns `value` unchanged after logging."
  @spec log(Types.string_like() | term(), value) :: value when value: var
  def log(label, value) do
    Logger.debug(fn -> "#{inspect(label)}: #{inspect(value)}" end)
    value
  end

  @spec todo(Types.string_like() | term()) :: no_return()
  def todo(label), do: raise "Debug.todo: #{inspect(label)}"

  @spec to_string(Types.string_like() | Types.wire_input()) :: String.t()
  def to_string(value), do: format_value(value)

  defp format_value(value) do
    case wire_shape(value) do
      {:ctor, name, []} -> name
      {:ctor, name, args} -> name <> " " <> Enum.map_join(args, " ", &format_value/1)
      {:list, items} -> "[" <> Enum.map_join(items, ", ", &format_value/1) <> "]"
      {:record, fields} -> "{" <> record_fields_to_string(fields) <> "}"
      :plain -> plain_to_string(value)
    end
  end

  defp wire_shape(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args),
    do: {:ctor, ctor, args}

  defp wire_shape(%{ctor: ctor, args: args}) when is_atom(ctor) and is_list(args),
    do: {:ctor, Atom.to_string(ctor), args}

  defp wire_shape({ctor, args}) when is_atom(ctor) and is_list(args),
    do: {:ctor, Atom.to_string(ctor), args}

  defp wire_shape(list) when is_list(list), do: {:list, list}
  defp wire_shape(map) when is_map(map), do: {:record, Map.to_list(map)}
  defp wire_shape(_), do: :plain

  defp record_fields_to_string(fields) do
    fields
    |> Enum.map_join(", ", fn
      {key, val} when is_atom(key) -> Atom.to_string(key) <> " = " <> format_value(val)
      {key, val} when is_binary(key) -> key <> " = " <> format_value(val)
    end)
  end

  defp plain_to_string(value) when is_binary(value), do: value
  defp plain_to_string(value) when is_integer(value), do: Integer.to_string(value)
  defp plain_to_string(value) when is_float(value), do: :erlang.float_to_binary(value, [:compact, decimals: 6])
  defp plain_to_string(true), do: "True"
  defp plain_to_string(false), do: "False"
  defp plain_to_string(value), do: inspect(value, limit: :infinity, printable_limit: :infinity)
end
