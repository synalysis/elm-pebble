defmodule Ide.Debugger.Types.SnapshotContinueEventPayload do
  @moduledoc "Payload for `debugger.snapshot_continue` cursor materialization events."
  alias Ide.Debugger.Types

  @type t :: %{
          optional(:cursor_seq) => non_neg_integer() | nil,
          optional(:source) => String.t(),
          optional(String.t()) => Types.wire_input()
        }

  @spec from_cursor(non_neg_integer() | nil, String.t()) :: t()
  def from_cursor(cursor_seq, source) when is_binary(source) do
    %{cursor_seq: cursor_seq, source: source}
  end
end
