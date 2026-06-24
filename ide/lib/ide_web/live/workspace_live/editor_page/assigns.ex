defmodule IdeWeb.WorkspaceLive.EditorPage.Assigns do
  @moduledoc false

  alias Ide.Compiler
  alias Ide.EditorCompletion.Types, as: CompletionTypes
  alias Ide.Projects.FileTypes
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.EditorDependencies
  alias IdeWeb.WorkspaceLive.EditorSupport.Types, as: EditorTypes

  @type pane ::
          :editor
          | :build
          | :debugger
          | :emulator
          | :publish
          | :settings
          | :resources
          | :packages
          | atom()

  @type flow_status :: :idle | :running | :ok | :error | atom() | nil
  @type tab :: EditorTypes.tab()
  @type diagnostic :: Compiler.diagnostic() | EditorTypes.diagnostic()

  @type t :: %{
          optional(:pane) => pane(),
          optional(:tree) => FileTypes.source_tree(),
          optional(:tabs) => [tab()],
          optional(:active_tab_id) => String.t() | nil,
          optional(:opening_file_id) => String.t() | nil,
          optional(:expanded_tree_dirs) => MapSet.t() | nil,
          optional(:editor_docs_panel_open) => boolean(),
          optional(:editor_docs_col_px) => non_neg_integer(),
          optional(:companion_app_present) => boolean(),
          optional(:project) => Project.t() | nil,
          optional(:rename_file_modal_open) => boolean(),
          optional(:rename_form) => EditorTypes.phoenix_form(),
          optional(:new_file_form) => EditorTypes.phoenix_form(),
          optional(:create_file_modal_open) => boolean(),
          optional(:create_file_source_roots) => [String.t()],
          optional(:editor_context_menu) => EditorTypes.context_menu_state() | nil,
          optional(:editor_check_status) => flow_status(),
          optional(:editor_check_output) => String.t() | nil,
          optional(:editor_inline_diagnostics) => [diagnostic()],
          optional(:active_diagnostic_index) => non_neg_integer() | nil,
          optional(:editor_doc_packages) => [CompletionTypes.doc_package_row()],
          optional(:editor_doc_package) => String.t() | nil,
          optional(:editor_doc_module) => String.t(),
          optional(:editor_doc_html) => String.t(),
          optional(:editor_doc_query) => String.t(),
          optional(:editor_tokenizer_mode) => atom(),
          optional(:editor_tokens) => [EditorTypes.tokenizer_token()],
          optional(:editor_fold_ranges) => [EditorTypes.fold_range()],
          optional(:editor_line_count) => pos_integer(),
          optional(:editor_token_diag_by_line) => EditorTypes.diagnostics_by_line(),
          optional(:editor_parser_panel) => boolean() | nil,
          optional(:editor_parser_payload) => EditorTypes.parser_payload(),
          optional(:editor_check_token) => EditorTypes.async_token(),
          optional(:editor_check_source_root) => String.t() | nil,
          optional(:editor_check_rel_path) => String.t() | nil,
          optional(:editor_deps_panel_open) => boolean(),
          optional(:packages_target_root) => String.t(),
          optional(:project_elm_direct) => [EditorDependencies.dependency_row()],
          optional(:project_elm_indirect) => [EditorDependencies.dependency_row()],
          optional(:editor_deps_usage_refresh_token) => EditorTypes.async_token(),
          optional(:editor_deps_docs_refresh_token) => EditorTypes.async_token(),
          optional(:format_status) => flow_status(),
          optional(:debug_mode) => boolean(),
          optional(:auto_format_on_save) => boolean(),
          optional(:editor_mode) => atom(),
          optional(:editor_theme) => atom(),
          optional(:editor_line_numbers) => boolean(),
          optional(:editor_active_line_highlight) => boolean(),
          optional(:editor_check_diagnostics) => [diagnostic()],
          optional(:format_output) => String.t() | nil,
          optional(:token_summary) => EditorTypes.token_summary() | nil,
          optional(:tokenizer_mode) => atom(),
          optional(:token_diagnostics) => [diagnostic()],
          optional(:myself) => %Phoenix.LiveComponent.CID{cid: pos_integer()} | nil,
          optional(atom()) => term()
        }
end
