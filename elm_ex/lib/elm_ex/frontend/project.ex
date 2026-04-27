defmodule ElmEx.Frontend.Project do
  @moduledoc """
  Typed metadata extracted from Elm project sources.
  """

  @type t() :: %__MODULE__{
          project_dir: String.t(),
          elm_json: map(),
          modules: [ElmEx.Frontend.Module.t()],
          diagnostics: [map()]
        }

  @enforce_keys [:project_dir, :elm_json, :modules]
  defstruct [:project_dir, :elm_json, :modules, diagnostics: []]
end
