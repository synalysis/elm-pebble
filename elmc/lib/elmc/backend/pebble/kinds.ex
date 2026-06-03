defmodule Elmc.Backend.Pebble.Kinds do
  @moduledoc false

  alias Elmc.Backend.Pebble.Util

  @draw_kinds [
    none: 0,
    clear: 2,
    pixel: 3,
    line: 4,
    rect: 5,
    fill_rect: 6,
    circle: 7,
    fill_circle: 8,
    push_context: 10,
    pop_context: 11,
    stroke_width: 12,
    antialiased: 13,
    stroke_color: 14,
    fill_color: 15,
    text_color: 16,
    round_rect: 17,
    arc: 18,
    context_group: 19,
    path_filled: 20,
    path_outline: 21,
    path_outline_open: 22,
    fill_radial: 23,
    compositing_mode: 24,
    bitmap_in_rect: 25,
    rotated_bitmap: 26,
    text_int_with_font: 27,
    text_label_with_font: 28,
    text: 29,
    vector_at: 30,
    vector_sequence_at: 31,
    bitmap_sequence_at: 32
  ]

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

  @run_modes [
    app: 0,
    watchface: 1
  ]

  @button_ids [
    back: 0,
    up: 1,
    select: 2,
    down: 3
  ]

  @accel_axes [
    x: 1,
    y: 2,
    z: 3
  ]

  @ui_node_kinds [
    window_stack: 1000,
    window_node: 1001,
    canvas_layer: 1002
  ]

  @draw_kind_ids Map.new(@draw_kinds)
  @command_kind_ids Map.new(@command_kinds)
  @run_mode_ids Map.new(@run_modes)
  @button_id_ids Map.new(@button_ids)
  @accel_axis_ids Map.new(@accel_axes)
  @ui_node_kind_ids Map.new(@ui_node_kinds)

  @type draw_kind ::
          :none
          | :clear
          | :pixel
          | :line
          | :rect
          | :fill_rect
          | :circle
          | :fill_circle
          | :push_context
          | :pop_context
          | :stroke_width
          | :antialiased
          | :stroke_color
          | :fill_color
          | :text_color
          | :round_rect
          | :arc
          | :context_group
          | :path_filled
          | :path_outline
          | :path_outline_open
          | :fill_radial
          | :compositing_mode
          | :bitmap_in_rect
          | :rotated_bitmap
          | :text_int_with_font
          | :text_label_with_font
          | :text
          | :vector_at
          | :vector_sequence_at
          | :bitmap_sequence_at
  @type command_kind :: atom()
  @type run_mode :: :app | :watchface
  @type button_id :: :back | :up | :select | :down
  @type accel_axis :: :x | :y | :z
  @type ui_node_kind :: :window_stack | :window_node | :canvas_layer

  @spec draw_kinds() :: keyword(non_neg_integer())
  def draw_kinds, do: @draw_kinds

  @spec command_kinds() :: keyword(non_neg_integer())
  def command_kinds, do: @command_kinds

  @spec run_modes() :: keyword(non_neg_integer())
  def run_modes, do: @run_modes

  @spec button_ids() :: keyword(non_neg_integer())
  def button_ids, do: @button_ids

  @spec accel_axes() :: keyword(non_neg_integer())
  def accel_axes, do: @accel_axes

  @spec ui_node_kinds() :: keyword(non_neg_integer())
  def ui_node_kinds, do: @ui_node_kinds

  @spec draw_kind_id!(draw_kind()) :: non_neg_integer()
  def draw_kind_id!(kind), do: Map.fetch!(@draw_kind_ids, kind)

  @spec draw_kind_c_name!(draw_kind() | non_neg_integer()) :: String.t()
  def draw_kind_c_name!(kind) when is_atom(kind) do
    "ELMC_PEBBLE_DRAW_#{Util.macro_name(Atom.to_string(kind))}"
  end

  def draw_kind_c_name!(id) when is_integer(id) do
    case Enum.find(@draw_kinds, fn {_kind, value} -> value == id end) do
      {kind, _value} -> draw_kind_c_name!(kind)
      nil -> raise KeyError, key: id, term: @draw_kinds
    end
  end

  @spec command_kind_id!(command_kind()) :: non_neg_integer()
  def command_kind_id!(kind), do: Map.fetch!(@command_kind_ids, kind)

  @spec run_mode_id!(run_mode()) :: non_neg_integer()
  def run_mode_id!(mode), do: Map.fetch!(@run_mode_ids, mode)

  @spec button_id!(button_id()) :: non_neg_integer()
  def button_id!(button), do: Map.fetch!(@button_id_ids, button)

  @spec accel_axis_id!(accel_axis()) :: non_neg_integer()
  def accel_axis_id!(axis), do: Map.fetch!(@accel_axis_ids, axis)

  @spec ui_node_kind_id!(ui_node_kind()) :: non_neg_integer()
  def ui_node_kind_id!(kind), do: Map.fetch!(@ui_node_kind_ids, kind)
end
