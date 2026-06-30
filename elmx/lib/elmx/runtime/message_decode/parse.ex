defmodule Elmx.Runtime.MessageDecode.Parse do
  @moduledoc false

  alias Elmx.Runtime.MessageDecode.Ctor
  alias Elmx.Types

  @spec decode(String.t(), Types.frame_tick_payload()) :: Types.elm_msg()
  def decode(message, frame_payload) when is_binary(message) do
    case String.split(message, " ", parts: 2) do
      [ctor, "(" <> rest] ->
        inner = rest |> String.trim_trailing(")") |> String.trim()
        {String.to_atom(ctor), parse_paren_payload(inner)}

      [ctor, rest] ->
        decode_with_rest(ctor, String.trim(rest))

      [ctor] ->
        decode_nullary(ctor, frame_payload)
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
          {int, ""} ->
            {atom, int}

          _ ->
            if Ctor.pascal_case_atom?(rest) do
              {atom, String.to_atom(rest)}
            else
              {atom, rest}
            end
        end
    end
  end

  defp decode_nullary(ctor, frame_payload) do
    atom = String.to_atom(ctor)

    if Ctor.frame_tick?(ctor) do
      {atom, frame_payload}
    else
      atom
    end
  end

  defp parse_paren_payload(content) when is_binary(content) do
    case String.split(content, " ", parts: 2) do
      [ctor, args_rest] -> Ctor.build(ctor, tokenize_args(args_rest))
      [ctor] -> String.to_atom(ctor)
    end
  end

  defp tokenize_args(rest) when is_binary(rest) do
    rest |> String.trim() |> tokenize_arg_tokens([]) |> Enum.map(&parse_arg_value/1)
  end

  defp parse_arg_value(value) when is_binary(value), do: Ctor.parse_scalar_token(value)
  defp parse_arg_value(value), do: value

  defp tokenize_arg_tokens("", acc), do: Enum.reverse(acc)

  defp tokenize_arg_tokens(rest, acc) do
    rest = String.trim_leading(rest)

    cond do
      rest == "" ->
        Enum.reverse(acc)

      String.starts_with?(rest, "(") ->
        {inner, remainder} = take_balanced_paren(rest)

        case String.split(inner, " ", parts: 2) do
          [single] ->
            tokenize_arg_tokens(remainder, [single | acc])

          [ctor, args_rest] ->
            nested = Ctor.build(ctor, tokenize_args(args_rest))
            tokenize_arg_tokens(remainder, [nested | acc])
        end

      true ->
        case String.split(rest, ~r/\s+/, parts: 2) do
          [token, more] -> tokenize_arg_tokens(more, [token | acc])
          [token] -> tokenize_arg_tokens("", [token | acc])
        end
    end
  end

  defp take_balanced_paren("(" <> rest) do
    do_take_balanced_paren(rest, 1, "")
  end

  defp do_take_balanced_paren("", _depth, inner), do: {inner, ""}

  defp do_take_balanced_paren(<<")", rest::binary>>, 1, inner), do: {inner, rest}

  defp do_take_balanced_paren(<<")", rest::binary>>, depth, inner),
    do: do_take_balanced_paren(rest, depth - 1, inner <> ")")

  defp do_take_balanced_paren(<<"(", rest::binary>>, depth, inner),
    do: do_take_balanced_paren(rest, depth + 1, inner <> "(")

  defp do_take_balanced_paren(<<char::utf8, rest::binary>>, depth, inner),
    do: do_take_balanced_paren(rest, depth, inner <> <<char::utf8>>)
end
