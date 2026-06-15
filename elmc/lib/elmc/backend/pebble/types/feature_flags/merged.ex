defmodule Elmc.Backend.Pebble.Types.FeatureFlags.Merged do
  @moduledoc false

  require Elmc.Backend.Pebble.Types.FeatureFlags.MapType
  import Elmc.Backend.Pebble.Types.FeatureFlags.MapType, only: [def_flags_type: 2]

  alias Elmc.Backend.Pebble.Types.FeatureFlags.Keys

  @type feature_flag :: boolean()

  def_flags_type feature_flags, Keys.all_keys()
end
