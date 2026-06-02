defmodule Elmx.Runtime.MessageDecode do
  @moduledoc """
  Decodes debugger wire step messages into Elm `Msg` values for generated `update/2`.
  """

  @spec decode(term(), term()) :: term()
  def decode(message, message_value \\ nil)

  def decode(message, message_value) do
    cond do
      not blank_message_value?(message_value) ->
        decode_wire_message(message_value, message)

      is_binary(message) ->
        decode_string_message(message)

      true ->
        message
    end
  end

  @spec default_frame_payload() :: map()
  def default_frame_payload do
    %{"dtMs" => 33, "elapsedMs" => 33, "frame" => 1}
  end

  @doc false
  @spec wire_to_runtime(term()) :: term()
  def wire_to_runtime(value), do: wire_to_runtime_value(value)

  defp decode_wire_message(%{"ctor" => "FromPhone", "args" => [inner | _]}, _message),
    do: {:FromPhone, wire_to_runtime_value(inner)}

  defp decode_wire_message(%{"ctor" => "FromPhone", "args" => []}, _message), do: :FromPhone

  defp decode_wire_message(wire, "FromPhone") when is_map(wire), do: {:FromPhone, wire_to_runtime_value(wire)}

  defp decode_wire_message(wire, message) when is_map(wire) do
    ctor = Map.get(wire, "ctor") || Map.get(wire, :ctor)

    cond do
      wire_message_matches_parent?(ctor, message) ->
        wire_to_runtime_value(wire)

      parent_wraps_payload?(message, ctor) ->
        {String.to_atom(message), wire_to_runtime_value(wire)}

      is_binary(message) and message != "" and (is_nil(ctor) or ctor == "") ->
        {String.to_atom(message_ctor(message)), wire_to_runtime_value(wire)}

      true ->
        wire_to_runtime_value(wire)
    end
  end

  defp decode_wire_message(wire, _message), do: wire

  defp decode_string_message(message) when is_binary(message) do
    case String.split(message, " ", parts: 2) do
      [ctor, "(" <> rest] ->
        inner = rest |> String.trim_trailing(")") |> String.trim()
        {String.to_atom(ctor), parse_paren_payload(inner)}

      [ctor, rest] ->
        decode_with_rest(ctor, String.trim(rest))

      [ctor] ->
        decode_nullary_string(ctor)
    end
  end

  defp decode_with_rest(ctor, rest) when is_binary(rest) do
    atom = String.to_atom(ctor)

    cond do
      String.starts_with?(rest, "{") ->
        case Jason.decode(rest) do
          {:ok, payload} when is_map(payload) -> {atom, payload}
          _ -> atom
        end

      rest == "True" or rest == "true" ->
        {atom, true}

      rest == "False" or rest == "false" ->
        {atom, false}

      true ->
        case Integer.parse(rest) do
          {int, ""} -> {atom, int}
          _ -> {atom, rest}
        end
    end
  end

  defp decode_nullary_string(ctor) do
    atom = ctor |> nullary_message_atom() |> String.to_atom()

    if frame_tick_ctor?(ctor) do
      {atom, default_frame_payload()}
    else
      atom
    end
  end

  # Debugger step strings are often lowercased ("inc"); Elm msg constructors are PascalCase ("Inc").
  defp nullary_message_atom(<<first::utf8, rest::binary>>) when first in ?a..?z do
    <<first - 32, rest::binary>>
  end

  defp nullary_message_atom(ctor) when is_binary(ctor), do: ctor

  defp parse_paren_payload(content) when is_binary(content) do
    case String.split(content, " ", parts: 2) do
      [ctor, args_rest] -> build_ctor_tuple(ctor, tokenize_args(args_rest))
      [ctor] -> String.to_atom(ctor)
    end
  end

  defp tokenize_args(rest) when is_binary(rest) do
    rest |> String.split(" ", trim: true) |> Enum.map(&parse_scalar_token/1)
  end

  defp parse_scalar_token(token) do
    cond do
      token == "true" ->
        true

      token == "false" ->
        false

      match?({_int, ""}, Integer.parse(token)) ->
        {int, ""} = Integer.parse(token)
        int

      pascal_case_atom?(token) ->
        String.to_atom(token)

      true ->
        token
    end
  end

  defp pascal_case_atom?(token) when is_binary(token) do
    Regex.match?(~r/^[A-Z][a-zA-Z0-9]*$/, token)
  end

  defp build_ctor_tuple(ctor, args) when is_binary(ctor) and is_list(args) do
    atom = String.to_atom(ctor)

    case args do
      [] -> atom
      [single] -> {atom, single}
      many -> List.to_tuple([atom | many])
    end
  end

  defp wire_to_runtime_value(%{"ctor" => "True", "args" => []}), do: true
  defp wire_to_runtime_value(%{"ctor" => "False", "args" => []}), do: false
  defp wire_to_runtime_value(%{"ctor" => "()", "args" => []}), do: nil

  defp wire_to_runtime_value(%{"ctor" => ctor, "args" => args})
       when is_binary(ctor) and is_list(args) do
    build_ctor_tuple(ctor, Enum.map(args, &wire_to_runtime_value/1))
  end

  defp wire_to_runtime_value(list) when is_list(list), do: Enum.map(list, &wire_to_runtime_value/1)

  defp wire_to_runtime_value(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), wire_to_runtime_value(v)} end)
  end

  defp wire_to_runtime_value(:True), do: true
  defp wire_to_runtime_value(:False), do: false
  defp wire_to_runtime_value(value), do: value

  defp wire_message_matches_parent?(ctor, message) when is_binary(ctor) and is_binary(message) do
    String.downcase(ctor) == String.downcase(message_ctor(message))
  end

  defp wire_message_matches_parent?(_ctor, _message), do: false

  @spec message_ctor(String.t()) :: String.t()
  defp message_ctor(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split(~r/[\s{(]/, parts: 2)
    |> List.first()
    |> to_string()
  end

  defp parent_wraps_payload?(_message, ctor) when ctor in ["Ok", "Err", "Nothing", "Just"], do: true
  defp parent_wraps_payload?(_message, _ctor), do: false

  defp blank_message_value?(nil), do: true
  defp blank_message_value?(map) when is_map(map), do: map_size(map) == 0
  defp blank_message_value?(_), do: false

  defp frame_tick_ctor?("FrameTick"), do: true
  defp frame_tick_ctor?(_), do: false
end
