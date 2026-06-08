defmodule IdeWeb.WorkspaceLive.DebuggerPreview.RuntimeAccess do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerPreview.Core

  defdelegate runtime_model(runtime), to: Core
  defdelegate primary_int_model_value(model), to: Core
  defdelegate text_label_from_node(node, model \\ %{}), to: Core
end
