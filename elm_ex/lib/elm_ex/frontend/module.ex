defmodule ElmEx.Frontend.Module do
  @moduledoc """
  Lightweight canonical-like module representation used by the backend.
  """

  alias ElmEx.Frontend.AstContract.Types.Declaration
  alias ElmEx.Frontend.Types.ImportEntry
  alias ElmEx.Types

  alias ElmEx.Frontend.AstContract.Types, as: AstTypes

  @type declaration_wire :: %{required(:kind) => atom(), optional(atom()) => AstTypes.invalid_input()}

  @type t() :: %__MODULE__{
          name: String.t(),
          path: String.t(),
          imports: [String.t()],
          declarations: [Declaration.t() | declaration_wire()],
          module_exposing: Types.module_exposing(),
          import_entries: [ImportEntry.t() | ImportEntry.wire_map()],
          port_module: boolean(),
          ports: [String.t()]
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
