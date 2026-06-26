defmodule Ide.EditorCompletion.Types do
  @moduledoc false

  alias Ide.PackageDocs.Types, as: PackageDocsTypes
  alias Ide.Packages.Types, as: PackageTypes

  @type dependency_row :: %{
          required(:name) => String.t(),
          required(:version) => String.t(),
          required(:builtin?) => boolean(),
          optional(:used?) => boolean() | nil
        }

  @type field_types :: %{optional(String.t()) => String.t()}

  @type type_entry :: %{
          required(:fields) => [String.t()],
          required(:field_types) => field_types()
        }

  @type package_type_maps :: %{optional(String.t()) => type_entry()}

  @type doc_package_row :: %{
          required(:package) => String.t(),
          required(:version) => String.t(),
          required(:modules) => [String.t()],
          required(:builtin?) => boolean(),
          required(:label) => String.t(),
          optional(:docs) => [PackageDocsTypes.module_doc()]
        }

  @type package_doc_index :: PackageTypes.module_index()

  @type completion_context :: %{
          optional(:prefix) => String.t() | nil,
          optional(:parser_payload) => Ide.Tokenizer.Types.parser_payload() | nil,
          optional(:token_tokens) => [Ide.Tokenizer.Types.token()],
          optional(:package_doc_index) => package_doc_index(),
          optional(:editor_doc_packages) => [doc_package_row()],
          optional(:package_type_maps) => package_type_maps(),
          optional(:direct_dependencies) => [dependency_row()],
          optional(:indirect_dependencies) => [dependency_row()],
          optional(:record_fields) => [String.t()],
          optional(:context_kind) => atom(),
          optional(:qualifier) => String.t() | nil,
          optional(:declaration_index) => Ide.EditorCompletionDeclarationIndex.t(),
          optional(:source) => String.t(),
          optional(:cursor_offset) => non_neg_integer(),
          optional(:limit) => pos_integer()
        }

end
