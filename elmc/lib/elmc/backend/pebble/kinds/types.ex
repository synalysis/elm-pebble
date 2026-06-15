defmodule Elmc.Backend.Pebble.Kinds.Types do
  @moduledoc false

  require Elmc.Backend.Pebble.Kinds.TypeGen
  import Elmc.Backend.Pebble.Kinds.TypeGen, only: [def_kind_union: 2]

  alias Elmc.Backend.Pebble.Kinds.Tables.{CommandKinds, DrawKinds, PlatformIds}

  def_kind_union draw_kind, DrawKinds.table()
  def_kind_union command_kind, CommandKinds.table()
  def_kind_union run_mode, PlatformIds.run_modes()
  def_kind_union button_id, PlatformIds.button_ids()
  def_kind_union accel_axis, PlatformIds.accel_axes()
  def_kind_union ui_node_kind, PlatformIds.ui_node_kinds()
end
