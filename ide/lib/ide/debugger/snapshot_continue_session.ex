defmodule Ide.Debugger.SnapshotContinueSession do
  @moduledoc false

  alias Ide.Debugger.Attrs
  alias Ide.Debugger.SnapshotContinue
  alias Ide.Debugger.Types

  @type append_event_fn ::
          (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
             Types.runtime_state())

  @spec apply(Types.runtime_state(), Types.snapshot_continue_attrs(), append_event_fn()) ::
          Types.runtime_state()
  def apply(state, attrs, append_event)
      when is_map(state) and is_map(attrs) and is_function(append_event, 3) do
    cursor_seq =
      Attrs.parse_optional_cursor_seq(Map.get(attrs, :cursor_seq) || Map.get(attrs, "cursor_seq"))

    SnapshotContinue.apply(state, cursor_seq, append_event)
  end
end
