defmodule Ide.Resources.ResourceStore.Manifest do
  @moduledoc false

  alias Ide.Resources.ResourceStore.Core

  defdelegate manifest_rel_path(), to: Core
  defdelegate generated_module_rel_path(), to: Core
  defdelegate ensure_generated(project), to: Core
  defdelegate ensure_generated_workspace(workspace), to: Core
end
