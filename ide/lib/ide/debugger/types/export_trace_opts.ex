defmodule Ide.Debugger.Types.ExportTraceOpts do
  @moduledoc """
  Options for `Debugger.export_trace/2`.
  """

  @type opt ::
          {:event_limit, pos_integer()}
          | {:compare_cursor_seq, non_neg_integer() | nil}
          | {:baseline_cursor_seq, non_neg_integer() | nil}

  @type opts :: [opt()]
end
