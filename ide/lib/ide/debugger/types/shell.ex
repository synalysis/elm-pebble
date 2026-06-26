defmodule Ide.Debugger.Types.Shell do
  @moduledoc """
  Debugger shell artifacts stored beside the app model (`RuntimeArtifacts.shell_map/1`).

  Keys match `RuntimeArtifacts.shell_artifact_keys/0`. Runtime maps often use string keys;
  typespecs use atoms for Dialyzer.
  """

  alias Ide.Debugger.Types
  alias ElmEx.DebuggerContract.Payload
  alias Ide.Debugger.RuntimeArtifacts.Types, as: ArtifactTypes

  @type t :: %{
          optional(:debugger_contract) => Payload.wire_payload(),
          optional(:debugger_contract_b64) => String.t(),
          optional(:debugger_contract_version) => String.t(),
          optional(:elm_introspect) => Payload.wire_payload(),
          optional(:elmx_manifest) => Types.elmx_manifest(),
          optional(:elmx_revision) => String.t(),
          optional(:vector_resource_indices) => ArtifactTypes.resource_indices(),
          optional(:bitmap_resource_indices) => ArtifactTypes.resource_indices(),
          optional(:animation_resource_indices) => ArtifactTypes.resource_indices(),
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()
end
