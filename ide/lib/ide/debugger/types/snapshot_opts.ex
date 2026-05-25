defmodule Ide.Debugger.Types.SnapshotOpts do
  @moduledoc """
  Options for `Debugger.snapshot/2`.
  """

  @type opt ::
          {:event_limit, pos_integer()}
          | {:types, [String.t()]}
          | {:since_seq, non_neg_integer()}

  @type opts :: [opt()]
end
