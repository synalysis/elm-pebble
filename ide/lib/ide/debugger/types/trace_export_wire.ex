defmodule Ide.Debugger.Types.TraceExportWire do
  @moduledoc """
  Canonical JSON wire rows for trace export (`export_version` 1 event list).

  Wire maps use **string keys** (`"seq"`, `"watch"`, `"snapshot_refs"`, etc.).
  """

  alias Ide.Debugger.Types

  @type snapshot_refs :: %{String.t() => non_neg_integer()}

  @type export_event_row :: %{
          optional(String.t()) =>
            Types.normalized_export_term()
            | snapshot_refs()
            | [String.t()]
            | integer()
            | String.t()
            | nil
        }

  @type wire_row :: export_event_row() | map()

  @type snapshot_reference_row :: %{
          optional(String.t()) => snapshot_refs() | [String.t()] | integer() | nil
        }
end
