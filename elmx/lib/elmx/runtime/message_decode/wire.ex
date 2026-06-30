defmodule Elmx.Runtime.MessageDecode.Wire do
  @moduledoc false

  alias Elmx.Runtime.MessageDecode.Ctor
  alias Elmx.Types

  @subscription_wrapper_ctors ~w(FromPhone FromWatch)

  @spec decode(Types.wire_value(), String.t() | Types.elm_msg() | nil) :: Types.elm_msg()
  def decode(%{"ctor" => "FromPhone", "args" => [inner | _]}, _message),
    do: {:FromPhone, to_runtime(inner)}

  def decode(%{"ctor" => "FromPhone", "args" => []}, _message), do: :FromPhone

  def decode(%{"ctor" => "FromWatch", "args" => [inner | _]}, _message),
    do: {:FromWatch, to_runtime(inner)}

  def decode(%{"ctor" => "FromWatch", "args" => []}, _message), do: :FromWatch

  def decode(wire, "FromPhone") when is_map(wire), do: {:FromPhone, to_runtime(wire)}

  def decode(wire, "FromWatch") when is_map(wire), do: {:FromWatch, to_runtime(wire)}

  def decode(wire, message) when is_map(wire) do
    ctor = Map.get(wire, "ctor") || Map.get(wire, :ctor)
    msg_ctor = if(is_binary(message), do: message_ctor(message), else: nil)

    cond do
      matches_parent?(ctor, message) ->
        to_runtime(wire)

      parent_wraps_payload?(message, ctor) ->
        {String.to_atom(msg_ctor), to_runtime(wire)}

      wraps_subscription_payload?(msg_ctor, ctor) ->
        {String.to_atom(msg_ctor), to_runtime(wire)}

      is_binary(message) and message != "" and (is_nil(ctor) or ctor == "") ->
        {String.to_atom(msg_ctor), to_runtime(wire)}

      true ->
        to_runtime(wire)
    end
  end

  def decode(wire, _message), do: wire

  @spec to_runtime(Types.wire_value()) :: Types.elm_msg()
  def to_runtime(%{"ctor" => "True", "args" => []}), do: true
  def to_runtime(%{"ctor" => "False", "args" => []}), do: false
  def to_runtime(%{"ctor" => "()", "args" => []}), do: nil

  def to_runtime(%{"ctor" => ctor, "args" => args})
      when is_binary(ctor) and is_list(args) do
    args = flatten_nested_nullary_union_args(args)
    Ctor.build(ctor, Enum.map(args, &to_runtime/1))
  end

  def to_runtime(%{"$ctor" => ctor, "$args" => args})
      when is_binary(ctor) and is_list(args) do
    args = flatten_nested_nullary_union_args(List.wrap(args))
    Ctor.build(ctor, Enum.map(args, &to_runtime/1))
  end

  def to_runtime(list) when is_list(list), do: Enum.map(list, &to_runtime/1)

  def to_runtime(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), to_runtime(v)} end)
  end

  def to_runtime(:True), do: true
  def to_runtime(:False), do: false
  def to_runtime(value), do: value

  @spec message_ctor(String.t()) :: String.t()
  def message_ctor(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split(~r/[\s{(]/, parts: 2)
    |> List.first()
    |> to_string()
  end

  defp matches_parent?(ctor, message) when is_binary(ctor) and is_binary(message) do
    String.downcase(ctor) == String.downcase(message_ctor(message))
  end

  defp matches_parent?(_ctor, _message), do: false

  defp parent_wraps_payload?(_message, ctor) when ctor in ["Ok", "Err", "Nothing", "Just"], do: true
  defp parent_wraps_payload?(_message, _ctor), do: false

  @spec wraps_subscription_payload?(String.t() | nil, String.t() | nil) :: boolean()
  defp wraps_subscription_payload?(msg_ctor, wire_ctor)
       when is_binary(msg_ctor) and is_binary(wire_ctor) and msg_ctor != wire_ctor do
    msg_ctor in @subscription_wrapper_ctors and Ctor.pascal_case_atom?(msg_ctor)
  end

  defp wraps_subscription_payload?(_msg_ctor, _wire_ctor), do: false

  @spec flatten_nested_nullary_union_args([Types.wire_value()]) :: [Types.wire_value()]
  defp flatten_nested_nullary_union_args([single | _] = args) when length(args) == 1 do
    case flatten_nullary_union_sibling_args(single, 2) do
      {:ok, flat} -> flat
      :error -> args
    end
  end

  defp flatten_nested_nullary_union_args(args) when is_list(args), do: args

  @spec flatten_nullary_union_sibling_args(Types.wire_value(), pos_integer()) ::
          {:ok, [Types.wire_value()]} | :error
  @result_wrapper_ctors ~w(Ok Err Just Nothing)

  defp flatten_nullary_union_sibling_args(%{"ctor" => outer, "args" => inner_args}, needed)
       when is_binary(outer) and outer not in @result_wrapper_ctors and is_list(inner_args) and
              needed > 1 do
    siblings =
      [%{"ctor" => outer, "args" => []}] ++ Enum.filter(inner_args, &nullary_union_ctor_wire?/1)

    if length(siblings) >= needed do
      {:ok, Enum.take(siblings, needed)}
    else
      :error
    end
  end

  defp flatten_nullary_union_sibling_args(%{ctor: outer, args: inner_args}, needed)
       when is_binary(outer) and is_list(inner_args) and needed > 1 do
    flatten_nullary_union_sibling_args(%{"ctor" => outer, "args" => inner_args}, needed)
  end

  defp flatten_nullary_union_sibling_args(_value, _needed), do: :error

  @spec nullary_union_ctor_wire?(Types.wire_value()) :: boolean()
  defp nullary_union_ctor_wire?(%{"ctor" => ctor, "args" => []}) when is_binary(ctor),
    do: Ctor.pascal_case_atom?(ctor)

  defp nullary_union_ctor_wire?(%{ctor: ctor, args: []}) when is_binary(ctor),
    do: Ctor.pascal_case_atom?(ctor)

  defp nullary_union_ctor_wire?(_value), do: false
end
