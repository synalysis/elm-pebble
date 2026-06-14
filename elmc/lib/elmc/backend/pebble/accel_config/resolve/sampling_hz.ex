defmodule Elmc.Backend.Pebble.AccelConfig.Resolve.SamplingHz do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes

  @spec from_record(CCodegenTypes.ir_expr(), pos_integer()) :: pos_integer()
  def from_record(%{op: :record_literal, fields: fields}, default) when is_list(fields) do
    case Enum.find(fields, &(&1.name == "samplingRate")) do
      %{expr: %{op: :int_literal, value: value}} when value in 1..4 ->
        hz_from_tag(value)

      %{expr: %{op: :int_literal, value: value}} when value in [10, 25, 50, 100] ->
        value

      %{expr: %{op: :qualified_var, target: target}} ->
        target |> String.split(".") |> List.last() |> hz_from_name(default)

      %{expr: %{op: :qualified_ref, target: target}} ->
        target |> String.split(".") |> List.last() |> hz_from_name(default)

      %{expr: %{op: :qualified_call, target: target, args: []}} ->
        target |> String.split(".") |> List.last() |> hz_from_name(default)

      %{expr: %{op: :constructor_call, target: target, args: []}} when is_binary(target) ->
        target |> String.split(".") |> List.last() |> hz_from_name(default)

      _ ->
        default
    end
  end

  def from_record(_, default), do: default

  @spec hz_from_name(String.t(), pos_integer()) :: pos_integer()
  defp hz_from_name("Hz10", _), do: 10
  defp hz_from_name("Hz25", _), do: 25
  defp hz_from_name("Hz50", _), do: 50
  defp hz_from_name("Hz100", _), do: 100
  defp hz_from_name("10", _), do: 10
  defp hz_from_name("25", _), do: 25
  defp hz_from_name("50", _), do: 50
  defp hz_from_name("100", _), do: 100
  defp hz_from_name(_, default), do: default

  @spec hz_from_tag(integer()) :: pos_integer()
  defp hz_from_tag(1), do: 10
  defp hz_from_tag(2), do: 25
  defp hz_from_tag(3), do: 50
  defp hz_from_tag(4), do: 100
  defp hz_from_tag(_), do: 25
end
