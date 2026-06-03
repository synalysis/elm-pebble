defmodule Elmc.Backend.Pebble.Util do
  @moduledoc false

  @spec macro_name(String.t()) :: String.t()
  def macro_name(name) do
    name
    |> String.replace(~r/[^A-Za-z0-9]/, "_")
    |> String.upcase()
  end

  @spec payload_arity_for_spec(String.t() | nil) :: non_neg_integer()
  def payload_arity_for_spec(nil), do: 0

  def payload_arity_for_spec(spec) when is_binary(spec) do
    normalized = spec |> String.trim() |> String.trim_leading("(") |> String.trim_trailing(")")

    cond do
      normalized == "" ->
        0

      String.contains?(normalized, "->") ->
        1

      String.contains?(normalized, ",") ->
        normalized |> String.split(",") |> length()

      true ->
        1
    end
  end
end
