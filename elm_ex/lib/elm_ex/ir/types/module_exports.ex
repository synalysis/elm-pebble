defmodule ElmEx.IR.Types.ModuleExports do
  @moduledoc """
  Module export metadata collected during `ElmEx.IR.Lowerer` import resolution.
  """

  @type union_constructors :: %{String.t() => [String.t()]}

  @type module_export :: %{
          required(:names) => [String.t()],
          required(:types) => [String.t()],
          required(:union_constructors) => union_constructors()
        }

  @type project_exports :: %{String.t() => module_export()}

  @type record_field_types :: %{String.t() => String.t() | nil}
end
