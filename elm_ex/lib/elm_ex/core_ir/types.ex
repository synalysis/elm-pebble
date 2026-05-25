defmodule ElmEx.CoreIR.Types do
  @moduledoc """
  Shared types for backend-stable normalized Core IR (`elm_ex.core_ir.v1`).
  """

  alias ElmEx.CoreIR.Types.{Declaration, Diagnostic, Expr, Module}

  @type diagnostic :: Diagnostic.t()
  @type declaration :: Declaration.t()
  @type module_t :: Module.t()
  @type expr :: Expr.t()

  @type normalized_module :: module_t()
  @type normalized_diagnostic :: diagnostic()
  @type normalized_value :: Expr.normalized_value()

  @type wire_map :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @type wire_core_ir :: wire_map() | ElmEx.CoreIR.t()
end
