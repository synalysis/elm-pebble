defmodule Elmc.Backend.Pebble.Types.FeatureFlags.Draw do
  @moduledoc false

  require Elmc.Backend.Pebble.Types.FeatureFlags.MapType
  import Elmc.Backend.Pebble.Types.FeatureFlags.MapType, only: [def_flags_type: 2]

  alias Elmc.Backend.Pebble.Types.FeatureFlags.Keys

  @type feature_flag :: boolean()

  def_flags_type primitive_flags, Keys.draw_primitive_keys()
  def_flags_type context_flags, Keys.draw_context_keys()
  def_flags_type text_flags, Keys.draw_text_keys()
  def_flags_type feature_flags, Keys.draw_keys()
end
