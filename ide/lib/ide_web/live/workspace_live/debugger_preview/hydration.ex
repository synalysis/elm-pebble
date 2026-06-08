defmodule IdeWeb.WorkspaceLive.DebuggerPreview.Hydration do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview.Core

  defdelegate hydrate_vector_svg_ops(rows, project), to: Core
  defdelegate resolve_bitmap_svg_ops(rows, runtime_or_project), to: Core
  defdelegate hydrate_animation_svg_ops(rows, project), to: Core
end
