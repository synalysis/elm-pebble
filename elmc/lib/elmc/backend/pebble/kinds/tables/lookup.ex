defmodule Elmc.Backend.Pebble.Kinds.Tables.Lookup do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec kind_for_id(Types.draw_kind_table(), non_neg_integer()) :: Types.draw_kind() | nil
  @spec kind_for_id(Types.command_kind_table(), non_neg_integer()) :: Types.command_kind() | nil
  @spec kind_for_id(Types.kind_table(), non_neg_integer()) :: atom() | nil
  def kind_for_id(table, id) do
    case Enum.find(table, fn {_kind, value} -> value == id end) do
      {kind, _value} -> kind
      nil -> nil
    end
  end
end
