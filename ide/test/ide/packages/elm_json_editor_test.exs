defmodule Ide.Packages.ElmJsonEditorTest do
  use Ide.DataCase, async: false

  alias Ide.Packages.ElmJsonEditor
  alias Ide.Packages
  alias Ide.Projects

  test "roots_for_package_management excludes protocol" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "PkgRoots",
               "slug" => "pkg-roots",
               "target_type" => "app"
             })

    roots = ElmJsonEditor.roots_for_package_management(project)
    assert "watch" in roots
    assert "phone" in roots
    refute "protocol" in roots
    assert Packages.package_elm_json_roots(project) == roots
  end

  defp resolver_opts do
    [
      source_root: "watch",
      versions_fetcher: fn
        "elm/http" -> {:ok, ["2.1.0", "2.0.0"]}
        "elm/url" -> {:ok, ["1.0.0"]}
        "elm/core" -> {:ok, ["1.0.5"]}
        "elm/json" -> {:ok, ["1.1.3"]}
        _ -> {:ok, ["1.0.0"]}
      end,
      release_fetcher: fn
        "elm/http", "2.1.0" ->
          {:ok,
           %{
             "dependencies" => %{
               "elm/core" => "1.0.0 <= v < 2.0.0",
               "elm/url" => "1.0.0 <= v < 2.0.0"
             }
           }}

        "elm/http", "2.0.0" ->
          {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}

        "elm/url", "1.0.0" ->
          {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}

        "elm/json", "1.1.3" ->
          {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}

        _, _ ->
          {:ok, %{"dependencies" => %{}}}
      end
    ]
  end

  test "preview and add package updates watch elm.json deterministically" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ElmJsonEditor",
               "slug" => "elm-json-editor",
               "target_type" => "app"
             })

    assert {:ok, preview} =
             ElmJsonEditor.preview_add(project, "elm/http", resolver_opts())

    assert preview.source_root == "watch"
    assert preview.package == "elm/http"
    assert preview.selected_version == "2.1.0"
    assert preview.existing_constraint == nil

    assert {:ok, result} =
             ElmJsonEditor.add_package(project, "elm/http", resolver_opts())

    assert result.changed == true
    assert result.previous_version == nil

    assert {:ok, content} = Projects.read_source_file(project, "watch", "elm.json")
    assert {:ok, decoded} = Jason.decode(content)
    assert decoded["dependencies"]["direct"]["elm/http"] == "2.1.0"
    assert decoded["dependencies"]["indirect"]["elm/url"] == "1.0.0"
  end

  test "add package preserves existing exact version when constrained" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ElmJsonExistingConstraint",
               "slug" => "elm-json-existing-constraint",
               "target_type" => "app"
             })

    assert :ok =
             Projects.write_source_file(
               project,
               "watch",
               "elm.json",
               Jason.encode!(
                 %{
                   "type" => "application",
                   "source-directories" => ["src"],
                   "elm-version" => "0.19.1",
                   "dependencies" => %{
                     "direct" => %{"elm/http" => "2.0.0"},
                     "indirect" => %{}
                   },
                   "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
                 },
                 pretty: true
               ) <> "\n"
             )

    assert {:ok, result} =
             ElmJsonEditor.add_package(project, "elm/http", resolver_opts())

    assert result.selected_version == "2.0.0"
    assert result.previous_version == "2.0.0"
    assert result.previous_version == "2.0.0"
  end
end
