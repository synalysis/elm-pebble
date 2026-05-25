defmodule Ide.Debugger.Types.ImportTraceBody do
  @moduledoc """
  Debugger trace export/import JSON body (`export_version` 1).
  """

  alias Ide.Debugger.Types
  alias Ide.Debugger.Surface

  @type export_version :: 1

  @type t :: %{
          optional(:export_version) => export_version(),
          optional(:project_slug) => String.t(),
          optional(:seq) => non_neg_integer(),
          optional(:running) => boolean(),
          optional(:revision) => String.t() | nil,
          optional(:watch_profile_id) => String.t(),
          optional(:launch_context) => map(),
          optional(:simulator_settings) => map(),
          optional(:watch) => Surface.surface_map() | map(),
          optional(:companion) => Surface.surface_map() | map(),
          optional(:phone) => Surface.surface_map() | map(),
          optional(:events) => [map()],
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | map()

  @type input :: String.t() | wire_map()
end
