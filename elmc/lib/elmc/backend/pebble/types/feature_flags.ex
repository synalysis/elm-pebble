defmodule Elmc.Backend.Pebble.Types.FeatureFlags do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types.FeatureFlags.{Command, Draw, Event, Keys, Merged}

  @type feature_flag :: boolean()
  @type feature_flag_key :: atom()

  @type command_storage_flags :: Command.storage_flags()
  @type command_timer_wakeup_flags :: Command.timer_wakeup_flags()
  @type command_backlight_flags :: Command.backlight_flags()
  @type command_time_timezone_flags :: Command.time_timezone_flags()
  @type command_device_query_flags :: Command.device_query_flags()
  @type command_logging_flags :: Command.logging_flags()
  @type command_system_flags :: Command.system_flags()
  @type command_vibes_flags :: Command.vibes_flags()
  @type command_health_flags :: Command.health_flags()
  @type command_device_services_flags :: Command.device_services_flags()
  @type command_services_flags :: Command.services_flags()
  @type command_feature_flags :: Command.feature_flags()

  @type draw_primitive_flags :: Draw.primitive_flags()
  @type draw_context_flags :: Draw.context_flags()
  @type draw_text_flags :: Draw.text_flags()
  @type draw_feature_flags :: Draw.feature_flags()

  @type event_clock_flags :: Event.clock_flags()
  @type event_input_flags :: Event.input_flags()
  @type event_constructor_platform_flags :: Event.constructor_platform_flags()
  @type event_subscription_platform_flags :: Event.subscription_platform_flags()
  @type event_platform_flags :: Event.platform_flags()
  @type event_feature_flags :: Event.feature_flags()
  @type compass_dispatch_flags :: Event.compass_dispatch_flags()

  @type feature_flags :: Merged.feature_flags()

  defdelegate command_keys, to: Keys
  defdelegate draw_keys, to: Keys
  defdelegate event_keys, to: Keys
  defdelegate command_storage_keys, to: Keys
  defdelegate command_system_keys, to: Keys
  defdelegate command_services_keys, to: Keys
  defdelegate command_timer_wakeup_keys, to: Keys
  defdelegate command_backlight_keys, to: Keys
  defdelegate command_time_timezone_keys, to: Keys
  defdelegate command_device_query_keys, to: Keys
  defdelegate command_logging_keys, to: Keys
  defdelegate command_vibes_keys, to: Keys
  defdelegate command_health_keys, to: Keys
  defdelegate command_device_services_keys, to: Keys
  defdelegate draw_primitive_keys, to: Keys
  defdelegate draw_context_keys, to: Keys
  defdelegate draw_text_keys, to: Keys
  defdelegate event_clock_keys, to: Keys
  defdelegate event_input_keys, to: Keys
  defdelegate event_platform_keys, to: Keys
  defdelegate event_constructor_platform_keys, to: Keys
  defdelegate event_subscription_platform_keys, to: Keys
  defdelegate all_keys, to: Keys
  defdelegate macro_name(key), to: Keys
end
