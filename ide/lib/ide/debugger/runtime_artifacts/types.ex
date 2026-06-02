defmodule Ide.Debugger.RuntimeArtifacts.Types do
  @moduledoc """
  Artifact fields merged onto runtime executor requests from execution models.
  """

  alias Ide.Debugger.Types

  @type resource_indices :: %{optional(String.t()) => pos_integer()}

  @type t :: %{
          optional(:elmx_manifest) => map(),
          optional(:elmx_revision) => String.t(),
          optional(:vector_resource_indices) => resource_indices(),
          optional(:bitmap_resource_indices) => resource_indices(),
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }
end
