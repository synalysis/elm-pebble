defmodule Ide.Resources.ResourceStore.GeneratedModule do
  @moduledoc false

  alias Ide.Resources.ResourceStore.Core

  defdelegate read_only_generated_module?(source_root, rel_path), to: Core
end
