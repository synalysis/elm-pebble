defmodule IdeWeb.WorkspaceLive.DebuggerPreview.CompactScene do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview.Core

  defdelegate compact_scene(runtime), to: Core
  defdelegate compact_scene(runtime, target), to: Core
  defdelegate compact_scene_diff(previous, current), to: Core
  defdelegate unresolved_summary(rows), to: Core
end
