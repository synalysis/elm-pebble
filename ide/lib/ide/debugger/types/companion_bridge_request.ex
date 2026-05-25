defmodule Ide.Debugger.Types.CompanionBridgeRequest do
  @moduledoc """
  Simulated companion bridge operation derived from introspect `Cmd` calls on phone/companion surfaces.
  """

  alias Ide.Debugger.Types
  @type t :: %{
          required(:api) => String.t(),
          required(:op) => String.t(),
          optional(:key) => String.t() | nil,
          optional(:value) => Types.companion_bridge_payload(),
          optional(:callback) => String.t() | nil,
          optional(:plain_result) => boolean(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_map :: t() | map()

  @type from_cmd_result :: [t()]
end
