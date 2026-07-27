defmodule Elmc.Backend.Pebble.FeatureFlags.MacroTable.DrawRows do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.Types.FeatureFlags.Keys

  @type macro_row :: {Types.c_macro_name(), Types.feature_flag_key()}

  @spec rows() :: [macro_row()]
  def rows do
    Keys.draw_keys()
    |> Enum.reject(&(&1 == :draw_text_any))
    |> Enum.map(&{Keys.macro_name(&1), &1})
  end
end
