defmodule Elmc.Backend.Pebble.Kinds.Tables.PlatformIds do
  @moduledoc false

  alias Elmc.Backend.Pebble.Kinds.Types, as: KindTypes
  alias Elmc.Backend.Pebble.Types

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

  @run_mode_ids Map.new(@run_modes)
  @button_id_ids Map.new(@button_ids)
  @accel_axis_ids Map.new(@accel_axes)
  @ui_node_kind_ids Map.new(@ui_node_kinds)

  @spec run_modes() :: Types.run_mode_table()
  def run_modes, do: @run_modes

  @spec button_ids() :: Types.button_id_table()
  def button_ids, do: @button_ids

  @spec accel_axes() :: Types.accel_axis_table()
  def accel_axes, do: @accel_axes

  @spec ui_node_kinds() :: Types.ui_node_kind_table()
  def ui_node_kinds, do: @ui_node_kinds

  @spec run_mode_id!(KindTypes.run_mode()) :: non_neg_integer()
  def run_mode_id!(mode), do: Map.fetch!(@run_mode_ids, mode)

  @spec button_id!(KindTypes.button_id()) :: non_neg_integer()
  def button_id!(button), do: Map.fetch!(@button_id_ids, button)

  @spec accel_axis_id!(KindTypes.accel_axis()) :: non_neg_integer()
  def accel_axis_id!(axis), do: Map.fetch!(@accel_axis_ids, axis)

  @spec ui_node_kind_id!(KindTypes.ui_node_kind()) :: non_neg_integer()
  def ui_node_kind_id!(kind), do: Map.fetch!(@ui_node_kind_ids, kind)
end
