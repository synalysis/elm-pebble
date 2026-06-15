defmodule Elmc.Backend.Pebble.Kinds.Tables.CommandKinds do
  @moduledoc false

  alias Elmc.Backend.Pebble.Kinds.Tables.Lookup
  alias Elmc.Backend.Pebble.Kinds.Types, as: KindTypes
  alias Elmc.Backend.Pebble.Types

  @command_kinds [
    none: 0,
    timer_after_ms: 1,
    storage_write_int: 2,
    storage_read_int: 3,
    storage_delete: 4,
    companion_send: 5,
    backlight: 6,
    get_current_time_string: 7,
    get_clock_style_24h: 8,
    get_timezone_is_set: 9,
    get_timezone: 10,
    get_watch_model: 11,
    get_firmware_version: 12,
    vibes_cancel: 13,
    vibes_short_pulse: 14,
    vibes_long_pulse: 15,
    vibes_double_pulse: 16,
    get_watch_color: 17,
    wakeup_schedule_after_seconds: 18,
    wakeup_cancel: 19,
    log_info_code: 20,
    log_warn_code: 21,
    log_error_code: 22,
    get_current_date_time: 23,
    get_battery_level: 24,
    get_connection_status: 25,
    storage_write_string: 26,
    storage_read_string: 27,
    random_generate: 28,
    health_value: 29,
    health_sum_today: 30,
    health_sum: 31,
    health_accessible: 32,
    vibes_custom_pattern: 33,
    data_log_bytes: 34,
    data_log_int32: 35,
    compass_peek: 36,
    dictation_start: 37,
    dictation_stop: 38,
    unobstructed_bounds_peek: 39,
    health_supported: 40
  ]

  @command_kind_ids Map.new(@command_kinds)

  @spec table() :: Types.command_kind_table()
  def table, do: @command_kinds

  @spec id!(KindTypes.command_kind()) :: non_neg_integer()
  def id!(kind), do: Map.fetch!(@command_kind_ids, kind)

  @spec for_id(non_neg_integer()) :: KindTypes.command_kind() | nil
  def for_id(id), do: Lookup.kind_for_id(@command_kinds, id)
end
