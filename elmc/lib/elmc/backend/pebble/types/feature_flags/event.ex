defmodule Elmc.Backend.Pebble.Types.FeatureFlags.Event do
  @moduledoc false

  require Elmc.Backend.Pebble.Types.FeatureFlags.MapType
  import Elmc.Backend.Pebble.Types.FeatureFlags.MapType, only: [def_flags_type: 2]

  alias Elmc.Backend.Pebble.Types.FeatureFlags.Keys

  @type feature_flag :: boolean()

  def_flags_type clock_flags, Keys.event_clock_keys()
  def_flags_type input_flags, Keys.event_input_keys()
  def_flags_type constructor_platform_flags, Keys.Event.constructor_platform_keys()
  def_flags_type subscription_platform_flags, Keys.Event.subscription_platform_keys()
  def_flags_type platform_flags, Keys.event_platform_keys()
  @type compass_dispatch_flags :: %{optional(:compass_events) => feature_flag()}
  def_flags_type feature_flags, Keys.event_keys()
end
