defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Types.NormalizedSvg do
  @moduledoc false

  alias Ide.Debugger.Types, as: DebuggerTypes

  @type svg_op_kind ::
          :push_context
          | :pop_context
          | :stroke_width
          | :antialiased
          | :stroke_color
          | :fill_color
          | :text_color
          | :compositing_mode
          | :clear
          | :round_rect
          | :rect
          | :fill_rect
          | :line
          | :arc
          | :fill_radial
          | :path_filled
          | :path_outline
          | :path_outline_open
          | :circle
          | :fill_circle
          | :pixel
          | :bitmap_in_rect
          | :rotated_bitmap
          | :vector_at
          | :vector_sequence_at
          | :vector_sequence_anim
          | :bitmap_sequence_at
          | :text_int
          | :text_label
          | :unresolved

  @typedoc "Atom-key draw op produced by view-tree normalization and SVG hydration."
  @type op :: %{
          required(:kind) => svg_op_kind(),
          optional(:node_type) => String.t(),
          optional(:provided_int_count) => non_neg_integer(),
          optional(:required_int_count) => non_neg_integer(),
          optional(:required_keys) => [String.t()],
          optional(:x) => integer(),
          optional(:y) => integer(),
          optional(:w) => integer(),
          optional(:h) => integer(),
          optional(:width) => integer(),
          optional(:height) => integer(),
          optional(:cx) => integer(),
          optional(:cy) => integer(),
          optional(:r) => integer(),
          optional(:radius) => integer(),
          optional(:x1) => integer(),
          optional(:y1) => integer(),
          optional(:x2) => integer(),
          optional(:y2) => integer(),
          optional(:start_angle) => integer(),
          optional(:end_angle) => integer(),
          optional(:angle) => integer(),
          optional(:color) => integer(),
          optional(:fill) => integer(),
          optional(:fill_color) => integer(),
          optional(:stroke_color) => integer(),
          optional(:text_color) => integer(),
          optional(:stroke_width) => pos_integer(),
          optional(:antialiased) => boolean(),
          optional(:compositing_mode) => non_neg_integer(),
          optional(:text) => String.t(),
          optional(:text_align) => String.t(),
          optional(:text_overflow) => String.t(),
          optional(:font_size) => integer(),
          optional(:offset_x) => integer(),
          optional(:offset_y) => integer(),
          optional(:rotation) => integer(),
          optional(:points) => [[integer()]] | list(),
          optional(:bitmap_id) => integer(),
          optional(:vector_id) => integer(),
          optional(:animation_id) => integer(),
          optional(:bitmap_animation_id) => integer(),
          optional(:src_w) => integer(),
          optional(:src_h) => integer(),
          optional(:center_x) => integer(),
          optional(:center_y) => integer(),
          optional(:value) => boolean() | integer(),
          optional(:svg_source) => String.t(),
          optional(:svg_resource) => String.t()
        }

  @type style :: %{
          optional(:stroke_color) => integer() | nil,
          optional(:fill_color) => integer() | nil,
          optional(:text_color) => integer() | nil,
          optional(:stroke_width) => pos_integer(),
          optional(:antialiased) => boolean(),
          optional(:compositing_mode) => non_neg_integer()
        }

  @type svg_op :: DebuggerTypes.view_output_row() | op()
end
