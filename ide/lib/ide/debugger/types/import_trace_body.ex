defmodule Ide.Debugger.Types.ImportTraceBody do
  @moduledoc """
  Debugger trace export/import JSON body (`export_version` 1).
  """

  alias Ide.Debugger.Surface
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.TraceExportWire

  @type export_version :: 1

  @type t :: %{
          optional(:export_version) => export_version(),
          optional(:project_slug) => String.t(),
          optional(:seq) => non_neg_integer(),
          optional(:running) => boolean(),
          optional(:revision) => String.t() | nil,
          optional(:watch_profile_id) => String.t(),
          optional(:launch_context) => Types.launch_context(),
          optional(:simulator_settings) => Types.simulator_settings(),
          optional(:watch) => Surface.surface_map(),
          optional(:companion) => Surface.surface_map(),
          optional(:phone) => Surface.surface_map(),
          optional(:events) => [TraceExportWire.export_event_row()],
          optional(String.t()) => Types.wire_input()
        }

  @typedoc "JSON-shaped map when atom-key `t/0` is unavailable at the wire boundary."
  @type wire_map :: t() | Types.wire_map()

  @type input :: String.t() | t() | Types.wire_map()
end
