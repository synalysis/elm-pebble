defmodule IdeWeb.WorkspaceLive.FlowDelegationTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.{
    BuildFlow,
    EditorFlow,
    EmulatorFlow,
    PackagesFlow,
    ProjectSettingsFlow,
    PublishPaneFlow,
    ResourcesFlow
  }

  defp assert_disjoint(lists) do
    all = Enum.flat_map(lists, & &1)
    dupes = all -- Enum.uniq(all)
    assert dupes == [], "overlapping workspace events: #{inspect(dupes)}"
  end

  test "pane flow event registries do not overlap" do
    assert_disjoint([
      EditorFlow.editor_events() ++ EditorFlow.file_tab_events(),
      ResourcesFlow.resource_events(),
      BuildFlow.build_events(),
      EmulatorFlow.emulator_events(),
      ProjectSettingsFlow.settings_events(),
      PublishPaneFlow.publish_events()
    ])
  end

  test "editor and file-tab events are handled by EditorFlow" do
    for event <- EditorFlow.editor_events() ++ EditorFlow.file_tab_events() do
      assert EditorFlow.handles?(event)
    end
  end

  test "resource and build events are handled by their flows" do
    for event <- ResourcesFlow.resource_events(), do: assert(ResourcesFlow.handles?(event))
    for event <- BuildFlow.build_events(), do: assert(BuildFlow.handles?(event))
  end

  test "publish and emulator events are handled by their flows" do
    for event <- PublishPaneFlow.publish_events(), do: assert(PublishPaneFlow.handles?(event))
    for event <- EmulatorFlow.emulator_events(), do: assert(EmulatorFlow.handles?(event))
  end

  test "build async names match BuildFlow registry" do
    assert BuildFlow.build_asyncs() == [
             :run_check,
             :run_build,
             :run_compile,
             :run_manifest,
             :run_pebble_build
           ]
  end

  test "flow async registries do not overlap" do
    lists = [
      BuildFlow.build_asyncs(),
      EditorFlow.editor_asyncs(),
      EmulatorFlow.emulator_asyncs(),
      PublishPaneFlow.publish_asyncs(),
      ProjectSettingsFlow.settings_asyncs(),
      PackagesFlow.packages_asyncs()
    ]

    all = Enum.flat_map(lists, & &1)
    dupes = all -- Enum.uniq(all)
    assert dupes == [], "overlapping workspace async names: #{inspect(dupes)}"
  end
end
