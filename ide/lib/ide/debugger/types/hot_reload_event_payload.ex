defmodule Ide.Debugger.Types.HotReloadEventPayload do
  @moduledoc """
  Payload for `debugger.reload` events after `Debugger.reload/2`.
  """

  alias Ide.Debugger.Types

  @type t :: %{
          optional(:reason) => String.t(),
          optional(:rel_path) => String.t() | nil,
          optional(:revision) => String.t(),
          optional(:source_root) => String.t(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | map()

  @spec from_reload(String.t(), String.t() | nil, String.t(), String.t()) :: t()
  def from_reload(reason, rel_path, revision, source_root)
      when is_binary(reason) and is_binary(revision) and is_binary(source_root) do
    %{
      reason: reason,
      rel_path: rel_path,
      revision: revision,
      source_root: source_root
    }
  end
end
