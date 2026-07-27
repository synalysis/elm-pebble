defmodule Elmc.Backend.Pebble.FeatureFlags.MacroTable.CommandRows do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.Types.FeatureFlags.Keys

  @type macro_row :: {Types.c_macro_name(), Types.feature_flag_key()}

  @spec rows() :: [macro_row()]
  def rows do
    Enum.map(Keys.command_keys(), &{Keys.macro_name(&1), &1})
  end
end
