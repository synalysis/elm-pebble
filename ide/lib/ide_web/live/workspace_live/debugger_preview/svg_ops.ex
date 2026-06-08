defmodule IdeWeb.WorkspaceLive.DebuggerPreview.SvgOps do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview.Core

  defdelegate svg_ops(tree, runtime), to: Core
  defdelegate resolve_bitmap_svg_op_id(op, bitmap_indices, animation_indices), to: Core
end
