defmodule Elmc.Backend.Pebble.Kinds.CNames do
  @moduledoc false

  alias Elmc.Backend.Pebble.Kinds.Tables
  alias Elmc.Backend.Pebble.Kinds.Types, as: KindTypes
  alias Elmc.Backend.Pebble.{Types, Util}

  @spec draw_kind_c_name!(KindTypes.draw_kind() | non_neg_integer()) :: Types.c_macro_name()
  def draw_kind_c_name!(kind) when is_atom(kind) do
    "ELMC_PEBBLE_DRAW_#{Util.macro_name(Atom.to_string(kind))}"
  end

  def draw_kind_c_name!(id) when is_integer(id) do
    case Tables.draw_kind_for_id(id) do
      nil -> raise KeyError, key: id, term: Tables.draw_kinds()
      kind -> draw_kind_c_name!(kind)
    end
  end

  @spec command_kind_c_name!(KindTypes.command_kind() | non_neg_integer()) :: Types.c_macro_name()
  def command_kind_c_name!(kind) when is_atom(kind) do
    "ELMC_PEBBLE_CMD_#{Util.macro_name(Atom.to_string(kind))}"
  end

  def command_kind_c_name!(id) when is_integer(id) do
    case Tables.command_kind_for_id(id) do
      nil -> raise KeyError, key: id, term: Tables.command_kinds()
      kind -> command_kind_c_name!(kind)
    end
  end
end
