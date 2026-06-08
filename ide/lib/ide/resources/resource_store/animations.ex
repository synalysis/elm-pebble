defmodule Ide.Resources.ResourceStore.Animations do
  @moduledoc false

  alias Ide.Resources.ResourceStore.Core

  defdelegate animation_file_path_by_id(project, id), to: Core
end
