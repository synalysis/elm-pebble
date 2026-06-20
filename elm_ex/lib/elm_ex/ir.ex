defmodule ElmEx.IR do
  @moduledoc """
  Compiler IR with explicit ownership annotations for RC insertion.
  """

  alias ElmEx.IR.Types

  @type t() :: Types.t()

  @enforce_keys [:modules]
  defstruct [:modules, diagnostics: []]
end

defmodule ElmEx.IR.Module do
  @moduledoc false

  alias ElmEx.IR.Types.Module, as: ModuleTypes

  @type t() :: ModuleTypes.t()

  @enforce_keys [:name, :imports, :declarations]
  defstruct [:name, :imports, :declarations, unions: %{}, ports: [], port_module: false]
end

defmodule ElmEx.IR.Declaration do
  @moduledoc false

  alias ElmEx.IR.Types.Declaration, as: DeclarationTypes

  @type t() :: DeclarationTypes.t()

  @enforce_keys [:kind, :name, :ownership]
  defstruct [:kind, :name, :type, :args, :expr, :span, ownership: []]
end
