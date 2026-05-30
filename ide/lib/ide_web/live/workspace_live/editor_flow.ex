defmodule IdeWeb.WorkspaceLive.EditorFlow do
  @moduledoc """
  Registry of editor-pane LiveView events slated for extraction from `WorkspaceLive`.

  Handlers still live in `WorkspaceLive` today; move them here in a follow-up pass
  (with `EditorSupport` helpers) without changing behavior.
  """

  @editor_events ~w(
    editor-change
    editor-key-edit
    editor-request-completions
    editor-submit
    format-file
    save-file
    editor-context-menu
    editor-context-dismiss
    editor-context-open-docs
    toggle-editor-docs-panel
    set-editor-docs-width
    editor-doc-package
    editor-doc-module
    editor-doc-search
    editor-state-changed
  )

  @file_tab_events ~w(
    open-file
    select-tab
    close-tab
    rename-file
    delete-file
    open-create-file-modal
    close-create-file-modal
    open-rename-file-modal
    close-rename-file-modal
    add-companion-app
  )

  @spec editor_events() :: [String.t()]
  def editor_events, do: @editor_events

  @spec file_tab_events() :: [String.t()]
  def file_tab_events, do: @file_tab_events

  @spec handles?(String.t()) :: boolean()
  def handles?(event) when is_binary(event),
    do: event in @editor_events or event in @file_tab_events
end
