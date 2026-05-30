#!/usr/bin/env python3
"""Apply WorkspaceLive flow delegations."""

from pathlib import Path

WS = Path(__file__).resolve().parents[1] / "lib/ide_web/live/workspace_live.ex"


def line_no(lines: list[str], needle: str) -> int:
    for i, line in enumerate(lines):
        if needle in line:
            return i + 1
    raise SystemExit(f"not found: {needle!r}")


def delete_range(lines: list[str], start: int, end: int) -> list[str]:
    return lines[: start - 1] + lines[end:]


def main() -> None:
    lines = WS.read_text().splitlines(keepends=True)

    # --- handle_event deletions (1-indexed inclusive end) ---
    event_deletes = [
        (line_no(lines, 'def handle_event("open-file"'), line_no(lines, 'def handle_event("upload-bitmap-resource"') - 1),
        (
            line_no(lines, 'def handle_event("upload-bitmap-resource"'),
            line_no(lines, '             "run-check"') - 1,
        ),
        (line_no(lines, 'def handle_event("packages-search"'), line_no(lines, 'def handle_event("open-create-file-modal"') - 1),
        (line_no(lines, 'def handle_event("open-create-file-modal"'), line_no(lines, 'def handle_event("run-pebble-build"') - 1),
        (line_no(lines, 'def handle_event("run-emulator-install"'), line_no(lines, 'def handle_event("update-release-summary"') - 1),
        (line_no(lines, 'def handle_event("update-release-summary"'), line_no(lines, 'def handle_event("set-emulator-target"') - 1),
        (line_no(lines, 'def handle_event("set-emulator-target"'), line_no(lines, "defp bitmap_import_opts") - 1),
        (line_no(lines, "defp submit_publish_release"), line_no(lines, "defp settings_save_section") - 1),
        (line_no(lines, "defp settings_save_section"), line_no(lines, "defp update_tab_by_id") - 1),
    ]

    for start, end in sorted(event_deletes, reverse=True):
        lines = delete_range(lines, start, end)

    # --- defp deletions before handle_async ---
    defp_start = line_no(lines, "defp update_tab_by_id")
    defp_end = line_no(lines, "@impl true") - 1
    while defp_end > defp_start and "handle_async" not in lines[defp_end - 1]:
        defp_end -= 1
    # find line before @impl true for handle_async
    defp_end = line_no(lines, "@spec handle_async(atom()") - 1
    lines = delete_range(lines, defp_start, defp_end)

    # --- handle_async deletions (between run_check and run_pebble_build / packages) ---
    async_start = line_no(lines, "def handle_async(:open_file,")
    async_end = line_no(lines, "def handle_async(:run_pebble_build,") - 1
    lines = delete_range(lines, async_start, async_end)

    # packages_search inline async if still present
    joined = "".join(lines)
    if "def handle_async(:packages_search, {:ok," in joined:
        ps = line_no(lines, "def handle_async(:packages_search, {:ok,")
        pe = line_no(lines, "def handle_async(:packages_inspect,") - 1
        lines = delete_range(lines, ps, pe)

    text = "".join(lines)

    if "alias IdeWeb.WorkspaceLive.EditorFlow" not in text:
        text = text.replace(
            "  alias IdeWeb.WorkspaceLive.EditorSupport\n",
            "  alias IdeWeb.WorkspaceLive.EditorSupport\n"
            "  alias IdeWeb.WorkspaceLive.EditorFlow\n"
            "  alias IdeWeb.WorkspaceLive.ProjectSettingsFlow\n"
            "  alias IdeWeb.WorkspaceLive.PublishPaneFlow\n",
            1,
        )

    if "@editor_flow_events" not in text:
        text = text.replace(
            "  @type dependency_row :: map()\n\n",
            "  @type dependency_row :: map()\n\n"
            "  @editor_flow_events EditorFlow.editor_events() ++ EditorFlow.file_tab_events()\n"
            "  @emulator_flow_events EmulatorFlow.emulator_events()\n"
            "  @project_settings_events ProjectSettingsFlow.settings_events()\n"
            "  @publish_pane_events PublishPaneFlow.publish_events()\n\n",
            1,
        )

    delegations = '''
  def handle_event(event, params, socket) when event in @editor_flow_events do
    EditorFlow.handle_event(event, params, socket)
  end

  def handle_event(event, params, socket)
      when event in [
             "upload-bitmap-resource",
             "clear-bitmap-variant",
             "validate-resource-upload",
             "delete-bitmap-resource",
             "upload-font-resource",
             "add-font-variant",
             "update-font-variant",
             "delete-font-resource",
             "delete-font-source"
           ] do
    ResourcesFlow.handle_event(event, params, socket)
  end

  def handle_event(event, params, socket)
      when event in [
             "run-check",
             "run-build",
             "run-compile",
             "run-manifest",
             "set-manifest-strict"
           ] do
    BuildFlow.handle_event(event, params, socket)
  end

  def handle_event("debugger-" <> _rest = event, params, socket) do
    DebuggerFlow.handle_event(event, params, socket)
  end

  def handle_event("simulator-save-settings", params, socket) do
    DebuggerFlow.handle_simulator_save_settings_event(params, socket)
  end

  def handle_event("packages-" <> _rest = event, params, socket) do
    PackagesFlow.handle_event(event, params, socket)
  end

  def handle_event(event, params, socket) when event in @emulator_flow_events do
    EmulatorFlow.handle_event(event, params, socket)
  end

  def handle_event(event, params, socket) when event in @project_settings_events do
    ProjectSettingsFlow.handle_event(event, params, socket)
  end

  def handle_event(event, params, socket) when event in @publish_pane_events do
    PublishPaneFlow.handle_event(event, params, socket)
  end

'''

    anchor = "  @impl true\n  @spec handle_event(String.t(), map(), socket())"
    if delegations.strip() not in text:
        text = text.replace(anchor, delegations + anchor, 1)

    async_block = '''
  def handle_async(async, result, socket)
      when async in [
             :open_file,
             :editor_check,
             :format_file,
             :refresh_editor_dependencies,
             :refresh_editor_dependency_usage
           ] do
    EditorFlow.handle_async(async, result, socket)
  end

  def handle_async(async, result, socket)
      when async in [
             :check_emulator_installation,
             :install_emulator_dependencies,
             :run_emulator_install,
             :stop_emulator,
             :external_emulator_control,
             :capture_screenshot,
             :capture_all_screenshots
           ] do
    EmulatorFlow.handle_async(async, result, socket)
  end

  def handle_async(async, result, socket)
      when async in [
             :prepare_release,
             :prepare_publish_artifact,
             :submit_publish_release,
             :push_project_snapshot,
             :export_publish_manifest,
             :export_release_notes
           ] do
    PublishPaneFlow.handle_async(async, result, socket)
  end

  def handle_async(async, result, socket)
      when async in [
             :sync_store_listing_metadata,
             :github_repo_status_check,
             :create_github_repository,
             :create_github_repository_and_push
           ] do
    ProjectSettingsFlow.handle_async(async, result, socket)
  end

'''

    needle = "    do: BuildFlow.handle_async(:run_check, result, socket)\n"
    if "EditorFlow.handle_async" not in text:
        text = text.replace(needle, needle + async_block, 1)

    # capture_all handle_info
    if "EmulatorFlow.handle_info({:capture_all_progress" not in text:
        start = text.index('  def handle_info({:capture_all_progress, token, msg}, socket)')
        end = text.index("  def handle_info({:packages_search_progress, token, msg}, socket)")
        text = (
            text[:start]
            + "  def handle_info({:capture_all_progress, token, msg}, socket) do\n"
            + "    EmulatorFlow.handle_info({:capture_all_progress, token, msg}, socket)\n"
            + "  end\n\n"
            + text[end:]
        )

    if "PackagesFlow.handle_async(:packages_search" not in text:
        text = text.replace(
            "  def handle_async(:packages_search, result, socket),",
            "  def handle_async(:packages_search, result, socket),\n"
            "    do: PackagesFlow.handle_async(:packages_search, result, socket)\n\n"
            "  def handle_async(:packages_search_removed, result, socket),",
            1,
        )
        text = text.replace(
            "  def handle_async(:packages_search_removed, result, socket),\n", "", 1
        )

    # Tail defp cleanup: editor doc, github format, emulator target at end
    for start_needle, end_needle in [
        ("  defp tab_with_save_content", "  defdelegate schedule_compiler_check"),
        ("  defp format_github_push_error", "  defdelegate bitmap_upload_output"),
        ("  defp default_emulator_target", "  defdelegate bitmap_upload_output"),
    ]:
        if start_needle in text and end_needle in text:
            s = text.index(start_needle)
            e = text.index(end_needle)
            if s < e:
                text = text[:s] + text[e:]

    extra_delegates = """  defdelegate refresh_github_repo_status(socket), to: ProjectSettingsFlow
  defdelegate default_emulator_target(), to: EmulatorFlow
  defdelegate maybe_check_emulator_installation(socket), to: EmulatorFlow
  defdelegate project_emulator_target(project), to: EmulatorFlow
  defdelegate project_emulator_mode(project), to: EmulatorFlow
  defdelegate assign_bitmap_resources(socket, project), to: ResourcesFlow
"""
    if "defdelegate refresh_github_repo_status" not in text:
        text = text.replace(
            "  defdelegate schedule_compiler_check(socket), to: BuildFlow\n",
            extra_delegates + "  defdelegate schedule_compiler_check(socket), to: BuildFlow\n",
            1,
        )

    text = text.replace(
        "|> assign(:bitmap_resources, load_bitmap_resources(project))",
        "|> assign_bitmap_resources(project)",
    )

    if "def render(assigns)" not in text:
        raise SystemExit("refusing to write: render/1 missing (deletion range too broad)")
    if "def handle_info(_msg, socket)" not in text and "def handle_info({:capture_all_progress" not in text:
        raise SystemExit("refusing to write: handle_info blocks missing")

    WS.write_text(text)
    print(f"OK: {len(text.splitlines())} lines")


if __name__ == "__main__":
    main()
