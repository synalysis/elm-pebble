defmodule Elmx.CompileResult do
  @moduledoc """
  In-memory compile output for IDE hot-reload and optional disk export.
  """

  alias Elmx.Types

  @type compiled_module :: %{
          required(:name) => String.t(),
          required(:source) => String.t(),
          required(:virtual_path) => String.t(),
          optional(:module) => module()
        }

  @type manifest_value ::
          String.t() | integer() | boolean() | list() | Types.wire_map()

  @type manifest :: %{optional(String.t()) => manifest_value()}

  @type diagnostic_row :: %{
          optional(String.t()) => manifest_value(),
          optional(atom()) => manifest_value()
        }

  @type t :: %__MODULE__{
          entry_module: module() | nil,
          entry_module_name: String.t(),
          generated_module_name: String.t(),
          modules: [compiled_module()],
          manifest: manifest(),
          ir: ElmEx.IR.t() | nil,
          diagnostics: [diagnostic_row()]
        }

  defstruct [
    :entry_module,
    entry_module_name: "Main",
    generated_module_name: "",
    modules: [],
    manifest: %{},
    ir: nil,
    diagnostics: []
  ]
end
