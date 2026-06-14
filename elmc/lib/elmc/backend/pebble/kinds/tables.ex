defmodule Elmc.Backend.Pebble.Kinds.Tables do
  @moduledoc false

  alias Elmc.Backend.Pebble.Kinds.Tables.{CommandKinds, DrawKinds, PlatformIds}
  alias Elmc.Backend.Pebble.Kinds.Types, as: KindTypes
  alias Elmc.Backend.Pebble.Types

  @spec draw_kinds() :: Types.draw_kind_table()
  defdelegate draw_kinds(), to: DrawKinds, as: :table

  @spec command_kinds() :: Types.command_kind_table()
  defdelegate command_kinds(), to: CommandKinds, as: :table

  @spec run_modes() :: Types.run_mode_table()
  defdelegate run_modes(), to: PlatformIds

  @spec button_ids() :: Types.button_id_table()
  defdelegate button_ids(), to: PlatformIds

  @spec accel_axes() :: Types.accel_axis_table()
  defdelegate accel_axes(), to: PlatformIds

  @spec ui_node_kinds() :: Types.ui_node_kind_table()
  defdelegate ui_node_kinds(), to: PlatformIds

  @spec draw_kind_id!(KindTypes.draw_kind()) :: non_neg_integer()
  defdelegate draw_kind_id!(kind), to: DrawKinds, as: :id!

  @spec command_kind_id!(KindTypes.command_kind()) :: non_neg_integer()
  defdelegate command_kind_id!(kind), to: CommandKinds, as: :id!

  @spec run_mode_id!(KindTypes.run_mode()) :: non_neg_integer()
  defdelegate run_mode_id!(mode), to: PlatformIds

  @spec button_id!(KindTypes.button_id()) :: non_neg_integer()
  defdelegate button_id!(button), to: PlatformIds

  @spec accel_axis_id!(KindTypes.accel_axis()) :: non_neg_integer()
  defdelegate accel_axis_id!(axis), to: PlatformIds

  @spec ui_node_kind_id!(KindTypes.ui_node_kind()) :: non_neg_integer()
  defdelegate ui_node_kind_id!(kind), to: PlatformIds

  @spec draw_kind_for_id(non_neg_integer()) :: KindTypes.draw_kind() | nil
  defdelegate draw_kind_for_id(id), to: DrawKinds, as: :for_id

  @spec command_kind_for_id(non_neg_integer()) :: KindTypes.command_kind() | nil
  defdelegate command_kind_for_id(id), to: CommandKinds, as: :for_id
end
