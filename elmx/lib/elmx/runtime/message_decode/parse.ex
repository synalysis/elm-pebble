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
    rest |> String.split(" ", trim: true) |> Enum.map(&Ctor.parse_scalar_token/1)
  end
end
