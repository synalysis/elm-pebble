defmodule Elmc.Backend.Pebble.Kinds do
  @moduledoc false

  alias Elmc.Backend.Pebble.Kinds.{CNames, Tables}
  alias Elmc.Backend.Pebble.Kinds.Types, as: KindTypes
  alias Elmc.Backend.Pebble.Types

  @type draw_kind :: KindTypes.draw_kind()
  @type command_kind :: KindTypes.command_kind()
  @type run_mode :: KindTypes.run_mode()
  @type button_id :: KindTypes.button_id()
  @type accel_axis :: KindTypes.accel_axis()
  @type ui_node_kind :: KindTypes.ui_node_kind()

  @spec draw_kinds() :: Types.draw_kind_table()
  defdelegate draw_kinds(), to: Tables

  @spec command_kinds() :: Types.command_kind_table()
  defdelegate command_kinds(), to: Tables

  @spec run_modes() :: Types.run_mode_table()
  defdelegate run_modes(), to: Tables

  @spec button_ids() :: Types.button_id_table()
  defdelegate button_ids(), to: Tables

  @spec accel_axes() :: Types.accel_axis_table()
  defdelegate accel_axes(), to: Tables

  @spec ui_node_kinds() :: Types.ui_node_kind_table()
  defdelegate ui_node_kinds(), to: Tables

  @spec draw_kind_id!(draw_kind()) :: non_neg_integer()
  defdelegate draw_kind_id!(kind), to: Tables

  @spec draw_kind_c_name!(draw_kind() | non_neg_integer()) :: Types.c_macro_name()
  defdelegate draw_kind_c_name!(kind), to: CNames

  @spec command_kind_id!(command_kind()) :: non_neg_integer()
  defdelegate command_kind_id!(kind), to: Tables

  @spec command_kind_c_name!(command_kind() | non_neg_integer()) :: Types.c_macro_name()
  defdelegate command_kind_c_name!(kind), to: CNames

  @spec run_mode_id!(run_mode()) :: non_neg_integer()
  defdelegate run_mode_id!(mode), to: Tables

  @spec button_id!(button_id()) :: non_neg_integer()
  defdelegate button_id!(button), to: Tables

  @spec accel_axis_id!(accel_axis()) :: non_neg_integer()
  defdelegate accel_axis_id!(axis), to: Tables

  @spec ui_node_kind_id!(ui_node_kind()) :: non_neg_integer()
  defdelegate ui_node_kind_id!(kind), to: Tables
end
