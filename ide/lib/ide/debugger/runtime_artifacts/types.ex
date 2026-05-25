defmodule Ide.Debugger.RuntimeArtifacts.Types do
  @moduledoc """
  Artifact fields merged onto semantic executor requests from execution models.
  """

  alias Ide.Debugger.Types

  @type resource_indices :: %{optional(String.t()) => pos_integer()}

  @type t :: %{
          optional(:elm_executor_metadata) => map(),
          optional(:elm_executor_core_ir) => Types.core_ir(),
          optional(:vector_resource_indices) => resource_indices(),
          optional(:bitmap_resource_indices) => resource_indices(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
end
