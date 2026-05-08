defmodule IdeWeb.WorkspaceLive.State do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [allow_upload: 3]

  alias Ide.Projects
  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.DebuggerSupport
  alias IdeWeb.WorkspaceLive.PublishFlow
  alias IdeWeb.WorkspaceLive.ToolchainPresenter

  @spec mount_defaults(Phoenix.LiveView.Socket.t(), term(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def mount_defaults(socket, settings, default_emulator_target) do
    socket
    |> assign(:project, nil)
    |> assign(:pane, :editor)
    |> assign(:tree, [])
    |> assign(:tabs, [])
    |> assign(:active_tab_id, nil)
    |> assign(:opening_file_id, nil)
    |> assign(:opening_file_label, nil)
    |> assign(:file_open_token, nil)
    |> assign(:editor_deps_refresh_token, nil)
    |> assign(:check_status, :idle)
    |> assign(:check_output, nil)
    |> assign(:compile_status, :idle)
    |> assign(:compile_output, nil)
    |> assign(:manifest_status, :idle)
    |> assign(:manifest_output, nil)
    |> assign(:build_status, :idle)
    |> assign(:build_output, nil)
    |> assign(:manifest_strict_mode, false)
    |> assign(:format_status, :idle)
    |> assign(:format_output, nil)
    |> assign(:pebble_build_status, :idle)
    |> assign(:pebble_build_output, nil)
    |> assign(:pebble_install_status, :idle)
    |> assign(:pebble_install_output, nil)
    |> assign(:emulator_installation_status, nil)
    |> assign(:emulator_dependency_install_status, :idle)
    |> assign(:emulator_dependency_install_output, nil)
    |> assign(:screenshot_status, :idle)
    |> assign(:screenshot_output, nil)
    |> assign(:capture_all_status, :idle)
    |> assign(:capture_all_output, nil)
    |> assign(:capture_all_progress, nil)
    |> assign(:capture_all_progress_lines, [])
    |> assign(:capture_all_target_statuses, %{})
    |> assign(:capture_all_token, nil)
    |> assign(:screenshots, [])
    |> assign(:screenshot_groups, [])
    |> assign(:emulator_targets, ToolchainPresenter.emulator_targets())
    |> assign(:selected_emulator_target, default_emulator_target)
    |> assign(:emulator_form, to_form(%{"target" => default_emulator_target}, as: :emulator))
    |> assign(:publish_status, :idle)
    |> assign(:publish_output, nil)
    |> assign(:publish_artifact_path, nil)
    |> assign(:publish_app_root, nil)
    |> assign(:publish_readiness, [])
    |> assign(:publish_checks, [])
    |> assign(:publish_summary, %{status: :idle, blockers: 0, warnings: 0, passed: 0})
    |> assign(:publish_warnings, [])
    |> assign(:publish_type_guidance, PublishFlow.publish_type_guidance(nil, nil))
    |> assign(:manifest_export_status, :idle)
    |> assign(:manifest_export_output, nil)
    |> assign(:manifest_export_path, nil)
    |> assign(:prepare_release_status, :idle)
    |> assign(:prepare_release_output, nil)
    |> assign(:publish_submit_status, :idle)
    |> assign(:publish_submit_output, nil)
    |> assign(:publish_submit_options, %{
      "is_published" => false,
      "all_platforms" => false
    })
    |> assign(:release_summary, PublishFlow.default_release_summary(nil))
    |> assign(
      :release_summary_form,
      to_form(PublishFlow.default_release_summary(nil), as: :release_summary)
    )
    |> assign(:publish_metrics, %{
      total_runs: 0,
      successful_runs: 0,
      last_duration_ms: nil,
      last_finished_at: nil,
      in_ide_completion_rate: "0.00"
    })
    |> assign(:packages_query, "")
    |> assign(:packages_search_results, [])
    |> assign(:packages_search_total, 0)
    |> assign(:packages_search_busy, false)
    |> assign(:packages_search_progress, nil)
    |> assign(:packages_search_token, nil)
    |> assign(:packages_inspect_loading, nil)
    |> assign(:packages_selected, nil)
    |> assign(:packages_details, nil)
    |> assign(:packages_versions, [])
    |> assign(:packages_readme, nil)
    |> assign(:packages_preview, nil)
    |> assign(:packages_target_root, "watch")
    |> assign(:packages_last_add_result, nil)
    |> assign(:create_file_modal_open, false)
    |> assign(:rename_file_modal_open, false)
    |> assign(:project_elm_direct, [])
    |> assign(:project_elm_indirect, [])
    |> assign(:package_doc_index, %{})
    |> assign(:editor_context_menu, nil)
    |> assign(:packages_dep_readme, nil)
    |> assign(:packages_dep_docs_package, nil)
    |> assign(:packages_dep_docs_version, nil)
    |> assign(:editor_docs_panel_open, false)
    |> assign(:editor_docs_col_px, 352)
    |> assign(:editor_doc_package, nil)
    |> assign(:editor_doc_module, "")
    |> assign(:editor_doc_query, "")
    |> assign(:editor_doc_packages, [])
    |> assign(:editor_doc_html, "")
    |> assign(:release_notes_status, :idle)
    |> assign(:release_notes_output, nil)
    |> assign(:release_notes_path, nil)
    |> assign(:token_summary, nil)
    |> assign(:token_tokens, [])
    |> assign(:token_diagnostics, [])
    |> assign(:formatter_parser_payload, nil)
    |> assign(:tokenizer_mode, :fast)
    |> assign(:editor_line_count, 1)
    |> assign(:token_diag_by_line, %{})
    |> assign(:editor_inline_diagnostics, [])
    |> assign(:active_diagnostic_index, nil)
    |> assign(:auto_format_on_save, settings.auto_format_on_save)
    |> assign(:formatter_backend, settings.formatter_backend)
    |> assign(:debug_mode, settings.debug_mode)
    |> assign(:editor_mode, settings.editor_mode)
    |> assign(:editor_theme, settings.editor_theme)
    |> assign(:editor_line_numbers, settings.editor_line_numbers)
    |> assign(:editor_active_line_highlight, settings.editor_active_line_highlight)
    |> assign(:debugger_auto_fire_refresh_scheduled, false)
    |> assign(:expanded_tree_dirs, MapSet.new())
    |> assign(
      :project_settings_form,
      to_form(project_settings_form_data(nil), as: :project_settings)
    )
    |> assign(:github_push_status, :idle)
    |> assign(:github_push_output, nil)
    |> assign(:auto_format_last_result, nil)
    |> assign(:bitmap_resources, [])
    |> assign(:bitmap_upload_output, nil)
    |> assign(:font_resources, [])
    |> assign(:font_upload_output, nil)
    |> assign(
      :new_file_form,
      to_form(%{"source_root" => "watch", "rel_path" => ""}, as: :new_file)
    )
    |> assign(:rename_form, to_form(%{"new_rel_path" => ""}, as: :rename))
    |> assign(:diagnostics, [])
    |> allow_upload(:bitmap,
      accept: ~w(.png .bmp .jpg .jpeg .gif .webp),
      max_entries: 1,
      max_file_size: 2_500_000
    )
    |> allow_upload(:font,
      accept: ~w(.ttf .otf),
      max_entries: 1,
      max_file_size: 2_500_000
    )
    |> DebuggerSupport.assign_defaults()
  end

  @spec assign_project(Phoenix.LiveView.Socket.t(), Project.t(), term(), map()) ::
          Phoenix.LiveView.Socket.t()
  def assign_project(socket, %Project{} = project, settings, data) when is_map(data) do
    publish_readiness = Map.fetch!(data, :publish_readiness)
    selected_emulator_target = Map.fetch!(data, :selected_emulator_target)

    socket
    |> assign(:project, project)
    |> DebuggerSupport.set_debugger_timeline_mode(Map.fetch!(data, :debugger_timeline_mode))
    |> assign(:debugger_trace_export, nil)
    |> assign(:debugger_trace_export_context, nil)
    |> assign(:debugger_export_form, DebuggerSupport.export_trace_form())
    |> assign(:debugger_import_form, DebuggerSupport.import_trace_form())
    |> assign(:pane, socket.assigns.live_action)
    |> assign(:tree, Map.fetch!(data, :tree))
    |> assign(:bitmap_resources, Map.fetch!(data, :bitmap_resources))
    |> assign(:font_resources, Map.fetch!(data, :font_resources))
    |> assign(:screenshots, Map.fetch!(data, :screenshots))
    |> assign(:screenshot_groups, Map.fetch!(data, :screenshot_groups))
    |> assign(:publish_readiness, publish_readiness)
    |> assign(:capture_all_target_statuses, socket.assigns.capture_all_target_statuses || %{})
    |> assign(:publish_summary, PublishFlow.publish_summary([], [], publish_readiness))
    |> assign(:publish_warnings, [])
    |> assign(
      :publish_type_guidance,
      PublishFlow.publish_type_guidance(project, publish_readiness)
    )
    |> assign(:release_summary, PublishFlow.default_release_summary(project))
    |> assign(
      :release_summary_form,
      to_form(PublishFlow.default_release_summary(project), as: :release_summary)
    )
    |> assign(:auto_format_on_save, settings.auto_format_on_save)
    |> assign(:formatter_backend, settings.formatter_backend)
    |> assign(:debug_mode, settings.debug_mode)
    |> assign(:editor_mode, settings.editor_mode)
    |> assign(:editor_theme, settings.editor_theme)
    |> assign(:editor_line_numbers, settings.editor_line_numbers)
    |> assign(:editor_active_line_highlight, settings.editor_active_line_highlight)
    |> assign(:expanded_tree_dirs, MapSet.new())
    |> assign(
      :project_settings_form,
      to_form(project_settings_form_data(project), as: :project_settings)
    )
    |> assign(:github_push_status, :idle)
    |> assign(:github_push_output, nil)
    |> assign(:packages_target_root, Map.fetch!(data, :packages_target_root))
    |> assign(:selected_emulator_target, selected_emulator_target)
    |> assign(:emulator_form, to_form(%{"target" => selected_emulator_target}, as: :emulator))
    |> assign(:page_title, "#{project.name} · #{Atom.to_string(socket.assigns.live_action)}")
  end

  @spec project_settings_form_data(term()) :: map()
  def project_settings_form_data(%Project{} = project) do
    defaults = project.release_defaults || %{}
    github = Projects.github_config(project)

    %{
      "version_label" => Map.get(defaults, "version_label", ""),
      "tags" => Map.get(defaults, "tags", ""),
      "github_owner" => Map.get(github, "owner", ""),
      "github_repo" => Map.get(github, "repo", ""),
      "github_branch" => Map.get(github, "branch", "main")
    }
  end

  def project_settings_form_data(_),
    do: %{
      "version_label" => "",
      "tags" => "",
      "github_owner" => "",
      "github_repo" => "",
      "github_branch" => "main"
    }
end
