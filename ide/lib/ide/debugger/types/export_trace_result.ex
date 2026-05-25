defmodule Ide.Debugger.Types.ExportTraceResult do
  @moduledoc """
  Return value of `Debugger.export_trace/2`.
  """

  @type t :: %{
          required(:json) => String.t(),
          required(:sha256) => String.t(),
          required(:byte_size) => non_neg_integer()
        }
end
