defmodule IdeWeb.WorkspaceLive.StateTest do
  use ExUnit.Case, async: true

  alias Ide.Projects.Project
  alias IdeWeb.WorkspaceLive.State

  test "detected_capabilities_from_project reads persisted release_defaults" do
    project = %Project{
      release_defaults: %{"capabilities" => ["location", "health", "location"]}
    }

    assert State.detected_capabilities_from_project(project) == ["location", "health"]
  end

  test "pane_only_navigation? is true when the same project is already loaded" do
    project = %Project{slug: "tangram"}

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, project: project, pane: :editor}
    }

    assert State.pane_only_navigation?(socket, project)
    refute State.pane_only_navigation?(socket, %Project{slug: "other"})
  end

  test "pane_only_navigation? is false when project is not loaded yet" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, project: nil}}

    refute State.pane_only_navigation?(socket, %Project{slug: "tangram"})
  end
end
