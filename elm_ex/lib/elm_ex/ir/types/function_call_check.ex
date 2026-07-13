defmodule ElmEx.IR.Types.FunctionCallCheck do
  @moduledoc """
  Types for `ElmEx.IR.FunctionCallCheck` import resolution and call-site analysis.
  """

  alias ElmEx.Frontend.AstContract.Types.Declaration, as: AstDeclaration
  alias ElmEx.Frontend.Module
  alias ElmEx.IR.Types.Diagnostic
  alias ElmEx.IR.Types.Lookup
  alias ElmEx.IR.Types.ModuleExports

  @type binding_types :: Lookup.name_map()

  @type signature_lookup :: %{String.t() => String.t()}

  @type type_alias_spec :: %{
          required(:fields) => [String.t()],
          required(:field_types) => %{String.t() => String.t()}
        }

  @type type_alias_lookup :: %{String.t() => type_alias_spec()}

  @type import_lookup :: %{
          required(:alias_map) => Lookup.name_map(),
          required(:import_unqualified_map) => Lookup.import_unqualified_map(),
          required(:type_unqualified_map) => Lookup.name_map(),
          required(:local_call_names) => MapSet.t(String.t()),
          required(:current_module) => String.t()
        }

  @type type_resolution_context ::
          import_lookup()
          | %{
              optional(:declaring_module) => String.t() | nil,
              optional(:alias_map) => Lookup.name_map(),
              optional(:type_unqualified_map) => Lookup.name_map(),
              optional(:current_module) => String.t()
            }

  @type occurrence_counts :: %{String.t() => non_neg_integer()}

  alias ElmEx.Frontend.AstContract.Types, as: AstTypes

  @type function_decl_context ::
          AstDeclaration.function_definition()
          | %{optional(atom()) => AstTypes.invalid_input(), optional(String.t()) => AstTypes.invalid_input()}

  @type call_context :: %{
          required(:module_name) => String.t(),
          required(:function_name) => String.t(),
          optional(:file) => String.t() | nil,
          optional(:module_path) => String.t() | nil,
          optional(:decl) => function_decl_context(),
          optional(:binding_types) => binding_types(),
          optional(:occurrence_counts) => occurrence_counts()
        }

  @type call_context_wire :: call_context() | call_context_partial()

  @type call_context_partial :: %{
          optional(atom()) => String.t() | integer() | boolean() | nil | MapSet.t(String.t()) | Lookup.name_map() | AstDeclaration.t(),
          optional(String.t()) => String.t() | integer() | boolean() | nil | MapSet.t(String.t()) | Lookup.name_map() | AstDeclaration.t()
        }

  @type diagnostics_result :: {[Diagnostic.t()], call_context_wire()}

  @type record_validation_issue ::
          {:extra_field, String.t()}
          | {:missing_field, String.t()}
          | {:field_type, String.t(), String.t(), String.t()}

  @type project_module_exports :: ModuleExports.project_exports()

  @type field_types_map :: %{String.t() => String.t()}
  @type name_map :: Lookup.name_map()

  @type frontend_module :: Module.t()

  @type import_resolution_maps :: Lookup.import_resolution_bundle()
end
