defmodule IdeWeb.WorkspaceLive.DebuggerPreview.Screen do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview.Core

  defdelegate screen_dimensions(runtime, tree \\ nil), to: Core
  defdelegate screen_round?(runtime, tree \\ nil), to: Core
end
