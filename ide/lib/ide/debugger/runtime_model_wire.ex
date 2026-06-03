defmodule Ide.Debugger.RuntimeModelWire do
  @moduledoc """
  Converts Elm wire encodings (`ctor`/`args`, `$ctor`, list spines) into plain JSON values.

  Used when merging executor patches and evaluating subscription guards against stored
  runtime fields. Does not backfill missing init fields or message payloads.
  """

  alias Ide.Debugger.Types

  @spec static_model_values(Types.inner_runtime_model()) :: Types.inner_runtime_model()
  def static_model_values(runtime_model) when is_map(runtime_model),
    do: hydrate_static_runtime_model_values(runtime_model)

  def static_model_values(runtime_model), do: runtime_model

  @spec static_value(Types.wire_input()) :: Types.wire_input()
  def static_value(value), do: hydrate_static_runtime_value(value)

  @spec wire_list_to_elixir(Types.protocol_ctor_value() | list()) :: list()
  def wire_list_to_elixir(value), do: elm_list_wire_to_elixir(value)

  @spec normalize_boolean_string(String.t()) :: boolean() | String.t()
  def normalize_boolean_string(value) when is_binary(value),
    do: normalize_runtime_boolean_string(value)

  @spec hydrate_static_runtime_model_values(Types.inner_runtime_model()) ::
          Types.inner_runtime_model()
  defp hydrate_static_runtime_model_values(runtime_model) when is_map(runtime_model) do
    runtime_model
    |> Enum.map(fn {key, value} ->
      case hydrate_static_runtime_value(value) do
        nil -> nil
        hydrated -> {key, hydrated}
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp hydrate_static_runtime_model_values(runtime_model), do: runtime_model

  @spec hydrate_static_runtime_value(Types.wire_input()) :: Types.wire_input()
  defp hydrate_static_runtime_value(%{} = value) do
    cond do
      Map.has_key?(value, "$ctor") ->
        ctor = to_string(Map.get(value, "$ctor") || "")
        args = Map.get(value, "$args") || []
        hydrate_constructor_value(ctor, args)

      Map.has_key?(value, "ctor") ->
        ctor = to_string(Map.get(value, "ctor") || "")
        args = Map.get(value, "args") || []
        hydrate_constructor_value(ctor, args)

      Map.has_key?(value, "$call") ->
        call = to_string(Map.get(value, "$call") || "")
        args = Map.get(value, "$args") || []
        args = if is_list(args), do: Enum.map(args, &hydrate_static_runtime_value/1), else: []

        case static_color_call_value(call, args) do
          {:ok, color} -> color
          :error -> nil
        end

      Map.has_key?(value, "call") or Map.has_key?(value, :call) ->
        nil

      true ->
        Map.new(value, fn {key, nested} -> {key, hydrate_static_runtime_value(nested)} end)
    end
  end

  defp hydrate_static_runtime_value(values) when is_list(values),
    do: Enum.map(values, &hydrate_static_runtime_value/1)

  defp hydrate_static_runtime_value(value) when is_binary(value),
    do: normalize_runtime_boolean_string(value)

  defp hydrate_static_runtime_value(value) when is_boolean(value), do: value
  defp hydrate_static_runtime_value(value), do: value

  @spec hydrate_constructor_value(String.t(), list()) :: Types.wire_input()
  defp hydrate_constructor_value(ctor, args) when is_binary(ctor) do
    args = if is_list(args), do: Enum.map(args, &hydrate_static_runtime_value/1), else: []

    case {ctor, args} do
      {"True", []} -> true
      {"False", []} -> false
      {"[]", []} -> []
      {"::", [head, tail]} -> [hydrate_static_runtime_value(head) | elm_list_wire_to_elixir(tail)]
      _ -> %{"ctor" => ctor, "args" => args}
    end
  end

  @spec elm_list_wire_to_elixir(Types.protocol_ctor_value() | list()) :: list()
  defp elm_list_wire_to_elixir([]), do: []

  defp elm_list_wire_to_elixir(%{"ctor" => "[]", "args" => []}), do: []

  defp elm_list_wire_to_elixir(%{"ctor" => "::", "args" => [head, tail]}) do
    [hydrate_static_runtime_value(head) | elm_list_wire_to_elixir(tail)]
  end

  defp elm_list_wire_to_elixir(%{ctor: "[]", args: []}), do: []

  defp elm_list_wire_to_elixir(%{ctor: "::", args: [head, tail]}) do
    [hydrate_static_runtime_value(head) | elm_list_wire_to_elixir(tail)]
  end

  defp elm_list_wire_to_elixir(list) when is_list(list),
    do: Enum.map(list, &hydrate_static_runtime_value/1)

  defp elm_list_wire_to_elixir(value), do: [hydrate_static_runtime_value(value)]

  @spec normalize_runtime_boolean_string(String.t()) :: boolean() | String.t()
  defp normalize_runtime_boolean_string(value) when is_binary(value) do
    case String.trim(value) do
      "True" -> true
      "False" -> false
      "true" -> true
      "false" -> false
      other -> other
    end
  end

  @spec static_color_call_value(String.t(), list()) :: {:ok, integer()} | :error
  defp static_color_call_value(call, []) when is_binary(call) do
    normalized = String.downcase(call)
    name = normalized |> String.split(".") |> List.last() |> to_string()

    cond do
      String.contains?(normalized, "color") ->
        static_color_constant(name)

      true ->
        :error
    end
  end

  defp static_color_call_value(_call, _args), do: :error

  @spec static_color_constant(String.t()) :: {:ok, integer()} | :error
  defp static_color_constant("black"), do: {:ok, 0xC0}
  defp static_color_constant("white"), do: {:ok, 0xFF}
  defp static_color_constant("red"), do: {:ok, 0xE0}
  defp static_color_constant("green"), do: {:ok, 0xCC}
  defp static_color_constant("blue"), do: {:ok, 0xC3}
  defp static_color_constant("clear"), do: {:ok, 0x00}
  defp static_color_constant(_name), do: :error
end
