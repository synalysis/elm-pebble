defmodule Elmc.Backend.CCodegen.PebbleMsgTag do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.Pebble.Util

  @spec tag_expr(Types.pattern()) :: String.t()
  def tag_expr(%{tag: tag} = pattern) when is_integer(tag) do
    case constructor_short_name(pattern) do
      name when is_binary(name) ->
        if msg_constructor?(name),
          do: "ELMC_PEBBLE_MSG_#{Util.macro_name(name)}",
          else: Integer.to_string(tag)

      _ ->
        Integer.to_string(tag)
    end
  end

  def tag_expr(_pattern), do: "0"

  @spec msg_constructor?(String.t()) :: boolean()
  def msg_constructor?(name) when is_binary(name) do
    MapSet.member?(Process.get(:elmc_pebble_msg_names, MapSet.new()), name)
  end

  defp constructor_short_name(%{name: name}) when is_binary(name), do: name

  defp constructor_short_name(%{resolved_name: name}) when is_binary(name) do
    name |> String.split(".") |> List.last()
  end

  defp constructor_short_name(_), do: nil
end
