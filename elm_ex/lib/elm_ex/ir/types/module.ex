defmodule ElmEx.IR.Types.Module do
  @moduledoc false

  alias ElmEx.IR.Types.{Declaration, UnionEntry}

  @type unions :: %{String.t() => UnionEntry.t() | map()}

  @type struct_t :: %ElmEx.IR.Module{
          name: String.t(),
          imports: [String.t()],
          declarations: [Declaration.t()],
          unions: unions()
        }

  @type t :: struct_t()
end
