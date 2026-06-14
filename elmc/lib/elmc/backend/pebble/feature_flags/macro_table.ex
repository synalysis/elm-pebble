defmodule Elmc.Backend.Pebble.FeatureFlags.MacroTable do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.FeatureFlags.MacroTable.{CommandRows, DrawRows, EventRows}

  @type macro_row :: {Types.c_macro_name(), Types.feature_flag_key()}

  @spec rows() :: [macro_row()]
  def rows do
    EventRows.rows() ++ CommandRows.rows() ++ DrawRows.rows()
  end

  @spec render(Types.feature_flags()) :: Types.c_source()
  def render(%{} = flags) do
    rows()
    |> Enum.map_join("\n", fn {macro, key} ->
      enabled = Map.fetch!(flags, key)
      "#define #{macro} #{if(enabled, do: 1, else: 0)}"
    end)
  end
end
