defmodule Ide.Resources.ResourceStore.Migration do
  @moduledoc false

  alias Ide.Resources.AnimationStore
  alias Ide.Resources.ResourceStore.{Bitmaps, Vectors}
  alias Ide.Resources.Types

  @spec migrate_all(Types.workspace_path()) :: :ok | {:error, Types.resource_error()}
  def migrate_all(workspace) when is_binary(workspace) do
    with :ok <- Bitmaps.migrate_manifest(workspace),
         :ok <- Vectors.migrate_manifest(workspace),
         :ok <- AnimationStore.migrate_manifest(workspace) do
      :ok
    end
  end
end
