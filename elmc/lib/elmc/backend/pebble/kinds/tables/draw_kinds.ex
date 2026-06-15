defmodule Elmc.Backend.Pebble.Kinds.Tables.DrawKinds do
  @moduledoc false

  alias Elmc.Backend.Pebble.Kinds.Tables.Lookup
  alias Elmc.Backend.Pebble.Kinds.Types, as: KindTypes
  alias Elmc.Backend.Pebble.Types

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

  @draw_kind_ids Map.new(@draw_kinds)

  @spec table() :: Types.draw_kind_table()
  def table, do: @draw_kinds

  @spec id!(KindTypes.draw_kind()) :: non_neg_integer()
  def id!(kind), do: Map.fetch!(@draw_kind_ids, kind)

  @spec for_id(non_neg_integer()) :: KindTypes.draw_kind() | nil
  def for_id(id), do: Lookup.kind_for_id(@draw_kinds, id)
end
