defmodule ElmEx.IR do
  @moduledoc """
  Compiler IR with explicit ownership annotations for RC insertion.
  """

  @type t() :: %__MODULE__{
          modules: [ElmEx.IR.Module.t()],
          diagnostics: [map()]
        }

  @enforce_keys [:modules]
  defstruct [:modules, diagnostics: []]
end

defmodule ElmEx.IR.Module do
  @moduledoc false

  @type t() :: %__MODULE__{
          name: String.t(),
          imports: [String.t()],
          declarations: [ElmEx.IR.Declaration.t()],
          unions: map()
        }

  @enforce_keys [:name, :imports, :declarations]
  defstruct [:name, :imports, :declarations, unions: %{}]
end

defmodule ElmEx.IR.Declaration do
  @moduledoc false

  @type t() :: %__MODULE__{
          kind: :function | :type_alias | :union,
          name: String.t(),
          type: String.t() | nil,
          args: [String.t()] | nil,
          expr: map() | nil,
          span: map() | nil,
          ownership: [atom()]
        }

  @enforce_keys [:kind, :name, :ownership]
  defstruct [:kind, :name, :type, :args, :expr, :span, ownership: []]
end
