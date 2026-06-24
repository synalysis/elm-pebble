defmodule ElmEx.IR.Types.FunctionCallCheck do
  @moduledoc """
  Types for `ElmEx.IR.FunctionCallCheck` import resolution and call-site analysis.
  """

  alias ElmEx.Frontend.Module
  alias ElmEx.IR.Types.Diagnostic
  alias ElmEx.IR.Types.Lookup

  @type binding_types :: Lookup.name_map()

  @type signature_lookup :: %{String.t() => String.t()}

  @type type_alias_spec :: %{
          required(:fields) => list(),
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

  @type call_context :: %{
          required(:module_name) => String.t(),
          required(:function_name) => String.t(),
          optional(:file) => String.t() | nil,
          optional(:module_path) => String.t() | nil,
          optional(:decl) => map(),
          optional(:binding_types) => binding_types(),
          optional(:occurrence_counts) => occurrence_counts()
        }

  @type call_context_wire :: call_context() | map()

  @type diagnostics_result :: {[Diagnostic.t()], call_context_wire()}

  @type record_validation_issue ::
          {:extra_field, String.t()}
          | {:missing_field, String.t()}
          | {:field_type, String.t(), String.t(), String.t()}

  @type project_module_exports :: %{String.t() => map()}

  @type field_types_map :: Lookup.name_map()
  @type name_map :: Lookup.name_map()

  @type frontend_module :: Module.t() | map()

  @type import_resolution_maps ::
          {Lookup.name_map(), Lookup.name_map(), [String.t()], Lookup.name_map()}
end
