defmodule ElmEx.IR.Types do
  @moduledoc """
  Re-export hub for `ElmEx.IR` struct and lowered IR maps.
  """

  alias ElmEx.IR.Types.{
    Declaration,
    Diagnostic,
    Expr,
    FunctionCallCheck,
    IR,
    Lookup,
    Module,
    ModuleExports,
    Pattern,
    UnionEntry,
    DeadCode,
    TopoSort
  }

  @type t :: IR.t()
  @type declaration :: Declaration.t()
  @type diagnostic :: Diagnostic.t()
  @type import_resolution_bundle :: Lookup.import_resolution_bundle()
  @type topo_dependency_graph :: TopoSort.dependency_graph()
  @type dead_code_function_key :: DeadCode.function_key()
  @type dead_code_function_map :: DeadCode.function_map()
  @type expr :: Expr.t()
  @type function_call_check_import_lookup :: FunctionCallCheck.import_lookup()
  @type function_call_check_signature_lookup :: FunctionCallCheck.signature_lookup()
  @type function_call_check_call_context :: FunctionCallCheck.call_context()
  @type import_resolution :: Lookup.import_resolution_t()
  @type lookup :: Lookup.t()
  @type module_exports :: ModuleExports.module_export()
  @type module_union_constructors :: ModuleExports.union_constructors()
  @type project_module_exports :: ModuleExports.project_exports()
  @type record_field_types :: ModuleExports.record_field_types()
  @type module_t :: Module.t()
  @type pattern :: Pattern.t()
  @type union_entry :: UnionEntry.t()
  @type unions :: Module.unions()
end
