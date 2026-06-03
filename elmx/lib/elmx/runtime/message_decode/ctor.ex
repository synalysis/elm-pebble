defmodule Elmx.Runtime.MessageDecode.Ctor do
  @moduledoc false

  alias Elmx.Types

  @spec build(String.t(), [term()]) :: Types.elm_msg()
  def build(ctor, args) when is_binary(ctor) and is_list(args) do
    atom = String.to_atom(ctor)

    case args do
      [] -> atom
      [single] -> {atom, single}
      many -> List.to_tuple([atom | many])
    end
  end

  @spec frame_tick?(String.t()) :: boolean()
  def frame_tick?("FrameTick"), do: true
  def frame_tick?(_), do: false

  @spec pascal_case_atom?(String.t()) :: boolean()
  def pascal_case_atom?(token) when is_binary(token) do
    Regex.match?(~r/^[A-Z][a-zA-Z0-9]*$/, token)
  end

  @spec parse_scalar_token(String.t()) :: term()
  def parse_scalar_token(token) do
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
end
