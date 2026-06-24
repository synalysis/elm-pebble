defmodule ElmEx.IR.Types do
  @moduledoc """
  Re-export hub for `ElmEx.IR` struct and lowered IR maps.
  """

  alias ElmEx.IR.Types.{Declaration, Diagnostic, Expr, IR, Lookup, Module, Pattern, UnionEntry}

  @type t :: IR.t()
  @type declaration :: Declaration.t()
  @type diagnostic :: Diagnostic.t()
  @type expr :: Expr.t()
  @type import_resolution :: Lookup.import_resolution_t()
  @type lookup :: Lookup.t()
  @type module_t :: Module.t()
  @type pattern :: Pattern.t()
  @type union_entry :: UnionEntry.t()
  @type unions :: Module.unions()
end
