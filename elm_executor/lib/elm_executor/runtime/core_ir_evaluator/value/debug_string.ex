defmodule ElmExecutor.Runtime.CoreIREvaluator.Value.DebugString do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Value.String, as: StringValue

  @spec elm_debug_to_string(term()) :: String.t()
  def elm_debug_to_string(value) when is_integer(value), do: Integer.to_string(value)
  def elm_debug_to_string(value) when is_float(value), do: StringValue.float_to_elm_string(value)
  def elm_debug_to_string(value) when is_boolean(value), do: if(value, do: "True", else: "False")

  def elm_debug_to_string(value) when is_binary(value) do
    if String.length(value) == 1 do
      "'#{value}'"
    else
      escaped = value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
      "\"#{escaped}\""
    end
  end

  def elm_debug_to_string(value) when is_list(value),
    do: "[" <> (value |> Enum.map(&elm_debug_to_string/1) |> Enum.join(",")) <> "]"

  def elm_debug_to_string(value) when is_tuple(value) do
    "(" <>
      (value |> Tuple.to_list() |> Enum.map(&elm_debug_to_string/1) |> Enum.join(", ")) <> ")"
  end

  def elm_debug_to_string(%{"ctor" => ctor, "args" => args})
      when is_binary(ctor) and is_list(args),
      do: short_ctor_name(ctor) <> format_ctor_args(args)

  def elm_debug_to_string(%{ctor: ctor, args: args}) when is_binary(ctor) and is_list(args),
    do: short_ctor_name(ctor) <> format_ctor_args(args)

  def elm_debug_to_string(value), do: inspect(value)

  @spec format_ctor_args(term()) :: String.t()
  defp format_ctor_args([]), do: ""

  defp format_ctor_args(args),
    do: " " <> (args |> Enum.map(&elm_debug_to_string/1) |> Enum.join(" "))

  @spec short_ctor_name(term()) :: String.t()
  defp short_ctor_name(target) when is_binary(target) do
    target
    |> String.split(".")
    |> List.last()
    |> to_string()
  end
end
