defmodule Elmc.Backend.Pebble.Util do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec macro_name(String.t()) :: Types.c_macro_name()
  def macro_name(name) do
    name
    |> String.replace(~r/[^A-Za-z0-9]/, "_")
    |> String.upcase()
  end

  @type payload_arity_spec :: String.t() | nil

  @spec payload_arity_for_spec(payload_arity_spec()) :: non_neg_integer()
  def payload_arity_for_spec(nil), do: 0

  @spec payload_arity_for_spec(String.t()) :: non_neg_integer()
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

  @spec direct_command_macro(Types.entry_module(), Types.decl_name()) :: Types.c_macro_name()
  def direct_command_macro(module_name, decl_name) do
    safe =
      "#{module_name}_#{decl_name}"
      |> String.replace(~r/[^A-Za-z0-9_]/, "_")
      |> String.upcase()

    "ELMC_HAVE_DIRECT_COMMANDS_#{safe}"
  end

  @spec entry_fn_name(Types.entry_module(), Types.decl_name()) :: Types.c_symbol()
  def entry_fn_name(entry_module, decl_name) do
    "elmc_fn_#{String.replace(entry_module, ".", "_")}_#{decl_name}"
  end
end
