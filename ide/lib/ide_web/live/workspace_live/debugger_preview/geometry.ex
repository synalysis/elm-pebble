defmodule IdeWeb.WorkspaceLive.DebuggerPreview.Geometry do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview.Core

  defdelegate svg_path_d(op, close_shape?), to: Core
  defdelegate arc_path(op), to: Core
  defdelegate pebble_color_to_svg(value, fallback \\ "#111111"), to: Core
end
