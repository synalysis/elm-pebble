defmodule IdeWeb.WorkspaceLive.DebuggerPreview do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview.CompactScene
  alias IdeWeb.WorkspaceLive.DebuggerPreview.Geometry
  alias IdeWeb.WorkspaceLive.DebuggerPreview.Hydration
  alias IdeWeb.WorkspaceLive.DebuggerPreview.RuntimeAccess
  alias IdeWeb.WorkspaceLive.DebuggerPreview.Screen
  alias IdeWeb.WorkspaceLive.DebuggerPreview.SvgOps

  defdelegate screen_dimensions(runtime, tree \\ nil), to: Screen
  defdelegate screen_round?(runtime, tree \\ nil), to: Screen

  defdelegate svg_ops(tree, runtime), to: SvgOps
  defdelegate resolve_bitmap_svg_op_id(op, bitmap_indices, animation_indices), to: SvgOps

  defdelegate hydrate_vector_svg_ops(rows, project), to: Hydration
  defdelegate resolve_bitmap_svg_ops(rows, runtime_or_project), to: Hydration
  defdelegate hydrate_animation_svg_ops(rows, project), to: Hydration

  defdelegate svg_path_d(op, close_shape?), to: Geometry
  defdelegate arc_path(op), to: Geometry
  defdelegate pebble_color_to_svg(value, fallback \\ "#111111"), to: Geometry

  defdelegate compact_scene(runtime), to: CompactScene
  defdelegate compact_scene(runtime, target), to: CompactScene
  defdelegate compact_scene_diff(previous, current), to: CompactScene
  defdelegate unresolved_summary(rows), to: CompactScene

  defdelegate runtime_model(runtime), to: RuntimeAccess
  defdelegate primary_int_model_value(model), to: RuntimeAccess
  defdelegate text_label_from_node(node, model \\ %{}), to: RuntimeAccess
end
