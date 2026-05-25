defmodule Ide.Debugger.Types.Shell do
  @moduledoc """
  Debugger shell artifacts stored beside the app model (`RuntimeArtifacts.shell_map/1`).

  Keys match `RuntimeArtifacts.shell_artifact_keys/0`. Runtime maps often use string keys;
  typespecs use atoms for Dialyzer.
  """

  alias ElmEx.CoreIR
  alias ElmEx.CoreIR.Types, as: CoreIRTypes
  alias Ide.Debugger.ElmIntrospect.Payload
  alias Ide.Debugger.RuntimeArtifacts.Types, as: ArtifactTypes

  @type t :: %{
          optional(:elm_introspect) => Payload.wire_payload(),
          optional(:elm_executor_core_ir) => CoreIR.t() | CoreIRTypes.wire_map() | nil,
          optional(:elm_executor_core_ir_b64) => String.t(),
          optional(:elm_executor_metadata) => map(),
          optional(:vector_resource_indices) => ArtifactTypes.resource_indices(),
          optional(:bitmap_resource_indices) => ArtifactTypes.resource_indices(),
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type wire_map :: t() | map()
end
