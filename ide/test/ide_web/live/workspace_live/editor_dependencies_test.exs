defmodule IdeWeb.WorkspaceLive.EditorDependenciesTest do
  use Ide.DataCase, async: false

  alias Ide.Projects
  alias IdeWeb.WorkspaceLive.EditorDependencies

  test "build_payload handles package-style dependency maps" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "EditorDepsPackageStyle",
               "slug" => "editor-deps-package-style",
               "target_type" => "app"
             })

    package_style =
      Jason.encode!(%{
        "type" => "package",
        "name" => "user/example",
        "summary" => "test",
        "license" => "BSD-3-Clause",
        "version" => "1.0.0",
        "exposed-modules" => [],
        "elm-version" => "0.19.0 <= v < 0.20.0",
        "dependencies" => %{
          "elm/core" => "1.0.0 <= v < 2.0.0",
          "elm/json" => "1.0.0 <= v < 2.0.0"
        },
        "test-dependencies" => %{}
      })

    assert :ok = Projects.write_source_file(project, "watch", "elm.json", package_style)

    payload = EditorDependencies.build_payload(project, "watch", "watch")
    names = Enum.map(payload.direct, & &1.name)

    assert "elm/core" in names
    assert "elm/json" in names
    assert payload.dependencies_available? == true
  end

  test "build_payload marks dependencies unavailable on invalid elm.json" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "EditorDepsInvalidJson",
               "slug" => "editor-deps-invalid-json",
               "target_type" => "app"
             })

    assert :ok = Projects.write_source_file(project, "watch", "elm.json", "{ invalid")

    payload = EditorDependencies.build_payload(project, "watch", "watch")
    assert payload.dependencies_available? == false
    assert payload.direct == []
    assert payload.indirect == []
  end
end
