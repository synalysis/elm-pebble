defmodule Elmx.CompileResult do
  @moduledoc """
  In-memory compile output for IDE hot-reload and optional disk export.
  """

  @type compiled_module :: %{
          required(:name) => String.t(),
          required(:source) => String.t(),
          required(:virtual_path) => String.t(),
          optional(:module) => module()
        }

  @type manifest :: %{
          optional(String.t()) => String.t() | integer() | boolean() | list() | map()
        }

  @type t :: %__MODULE__{
          entry_module: module() | nil,
          entry_module_name: String.t(),
          generated_module_name: String.t(),
          modules: [compiled_module()],
          manifest: manifest(),
          ir: ElmEx.IR.t() | nil,
          diagnostics: [map()]
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
