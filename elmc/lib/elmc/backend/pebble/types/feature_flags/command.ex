defmodule Elmc.Backend.Pebble.Types.FeatureFlags.Command do
  @moduledoc false

  require Elmc.Backend.Pebble.Types.FeatureFlags.MapType
  import Elmc.Backend.Pebble.Types.FeatureFlags.MapType, only: [def_flags_type: 2]

  alias Elmc.Backend.Pebble.Types.FeatureFlags.Keys

  @type feature_flag :: boolean()

  def_flags_type storage_flags, Keys.command_storage_keys()
  def_flags_type timer_wakeup_flags, Keys.Command.timer_wakeup_keys()
  def_flags_type backlight_flags, Keys.Command.backlight_keys()
  def_flags_type time_timezone_flags, Keys.Command.time_timezone_keys()
  def_flags_type device_query_flags, Keys.Command.device_query_keys()
  def_flags_type logging_flags, Keys.Command.logging_keys()
  def_flags_type system_flags, Keys.command_system_keys()
  def_flags_type vibes_flags, Keys.Command.vibes_keys()
  def_flags_type health_flags, Keys.Command.health_keys()
  def_flags_type device_services_flags, Keys.Command.device_services_keys()
  def_flags_type speaker_flags, Keys.Command.speaker_keys()
  def_flags_type services_flags, Keys.command_services_keys()
  def_flags_type feature_flags, Keys.command_keys()
end
