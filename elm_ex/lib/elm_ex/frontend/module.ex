defmodule ElmEx.Frontend.Module do
  @moduledoc """
  Lightweight canonical-like module representation used by the backend.
  """

  alias ElmEx.Types

  @type t() :: %__MODULE__{
          name: String.t(),
          path: String.t(),
          imports: [String.t()],
          declarations: [map()],
          module_exposing: Types.module_exposing(),
          import_entries: [map()],
          port_module: boolean(),
          ports: [map()]
        }

  @enforce_keys [:name, :path, :imports, :declarations]
  defstruct [
    :name,
    :path,
    :imports,
    :declarations,
    module_exposing: nil,
    import_entries: [],
    port_module: false,
    ports: []
  ]
end
