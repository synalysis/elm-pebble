defmodule ElmEx.IR.Types do
  @moduledoc """
  Re-export hub for `ElmEx.IR` struct and lowered IR maps.
  """

  alias ElmEx.IR.Types.{Declaration, Diagnostic, IR, Module, UnionEntry}

  @type t :: IR.t()
  @type declaration :: Declaration.t()
  @type diagnostic :: Diagnostic.t()
  @type module_t :: Module.t()
  @type union_entry :: UnionEntry.t()
  @type unions :: Module.unions()
end
