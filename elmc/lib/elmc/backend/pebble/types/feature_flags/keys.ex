defmodule Elmc.Backend.Pebble.Types.FeatureFlags.Keys do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.Types.FeatureFlags.Keys.{Command, Draw, Event}

  @spec command_keys() :: [Types.feature_flag_key()]
  defdelegate command_keys(), to: Command, as: :keys

  @spec draw_keys() :: [Types.feature_flag_key()]
  defdelegate draw_keys(), to: Draw, as: :keys

  @spec event_keys() :: [Types.feature_flag_key()]
  defdelegate event_keys(), to: Event, as: :keys

  @spec all_keys() :: [Types.feature_flag_key()]
  def all_keys, do: Command.keys() ++ Draw.keys() ++ Event.keys()

  @spec command_storage_keys() :: [Types.feature_flag_key()]
  defdelegate command_storage_keys(), to: Command, as: :storage_keys

  @spec command_system_keys() :: [Types.feature_flag_key()]
  defdelegate command_system_keys(), to: Command, as: :system_keys

  @spec command_services_keys() :: [Types.feature_flag_key()]
  defdelegate command_services_keys(), to: Command, as: :services_keys

  @spec command_timer_wakeup_keys() :: [Types.feature_flag_key()]
  defdelegate command_timer_wakeup_keys(), to: Command, as: :timer_wakeup_keys

  @spec command_backlight_keys() :: [Types.feature_flag_key()]
  defdelegate command_backlight_keys(), to: Command, as: :backlight_keys

  @spec command_time_timezone_keys() :: [Types.feature_flag_key()]
  defdelegate command_time_timezone_keys(), to: Command, as: :time_timezone_keys

  @spec command_device_query_keys() :: [Types.feature_flag_key()]
  defdelegate command_device_query_keys(), to: Command, as: :device_query_keys

  @spec command_logging_keys() :: [Types.feature_flag_key()]
  defdelegate command_logging_keys(), to: Command, as: :logging_keys

  @spec command_vibes_keys() :: [Types.feature_flag_key()]
  defdelegate command_vibes_keys(), to: Command, as: :vibes_keys

  @spec command_health_keys() :: [Types.feature_flag_key()]
  defdelegate command_health_keys(), to: Command, as: :health_keys

  @spec command_device_services_keys() :: [Types.feature_flag_key()]
  defdelegate command_device_services_keys(), to: Command, as: :device_services_keys

  @spec draw_primitive_keys() :: [Types.feature_flag_key()]
  defdelegate draw_primitive_keys(), to: Draw, as: :primitive_keys

  @spec draw_context_keys() :: [Types.feature_flag_key()]
  defdelegate draw_context_keys(), to: Draw, as: :context_keys

  @spec draw_text_keys() :: [Types.feature_flag_key()]
  defdelegate draw_text_keys(), to: Draw, as: :text_keys

  @spec event_clock_keys() :: [Types.feature_flag_key()]
  defdelegate event_clock_keys(), to: Event, as: :clock_keys

  @spec event_input_keys() :: [Types.feature_flag_key()]
  defdelegate event_input_keys(), to: Event, as: :input_keys

  @spec event_platform_keys() :: [Types.feature_flag_key()]
  defdelegate event_platform_keys(), to: Event, as: :platform_keys

  @spec event_constructor_platform_keys() :: [Types.feature_flag_key()]
  defdelegate event_constructor_platform_keys(), to: Event, as: :constructor_platform_keys

  @spec event_subscription_platform_keys() :: [Types.feature_flag_key()]
  defdelegate event_subscription_platform_keys(), to: Event, as: :subscription_platform_keys

  @spec macro_name(Types.feature_flag_key()) :: Types.c_macro_name()
  def macro_name(key) when is_atom(key) do
    ("ELMC_PEBBLE_FEATURE_" <> Atom.to_string(key)) |> String.upcase()
  end
end
