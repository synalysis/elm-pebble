defmodule ElmEx.Frontend.Project do
  @moduledoc """
  Typed metadata extracted from Elm project sources.
  """

  alias ElmEx.Frontend.Bridge.Types, as: BridgeTypes
  alias ElmEx.Types

  @type project_diagnostic ::
          Types.elm_report() | BridgeTypes.lowerer_warning() | BridgeTypes.lowerer_diagnostic()

  @type t() :: %__MODULE__{
          project_dir: String.t(),
          elm_json: Types.elm_json(),
          modules: [ElmEx.Frontend.Module.t()],
          diagnostics: [project_diagnostic()]
        }

  @enforce_keys [:project_dir, :elm_json, :modules]
  defstruct [:project_dir, :elm_json, :modules, diagnostics: []]
end
