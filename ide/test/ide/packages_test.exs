defmodule Ide.PackagesTest do
  use Ide.DataCase, async: false

  alias Ide.Packages
  alias Ide.Projects

  defmodule MockProvider do
    @behaviour Ide.Packages.Provider

    @impl true
    def search(query, _opts) do
      entries = [
        %{name: "elm/core", summary: "Elm core", license: "BSD-3-Clause", version: "1.0.5"},
        %{name: "elm/http", summary: "HTTP", license: "BSD-3-Clause", version: "2.0.0"},
        %{name: "elm/html", summary: "HTML", license: "BSD-3-Clause", version: "2.0.0"}
      ]

      q = String.downcase(String.trim(query || ""))
      {:ok, Enum.filter(entries, fn entry -> q == "" or String.contains?(entry.name, q) end)}
    end

    @impl true
    def package_details("elm/no-details", _opts), do: {:error, :details_should_not_be_called}

    def package_details("elm-pebble/elm-watch", _opts) do
      {:ok,
       %{
         name: "elm-pebble/elm-watch",
         summary: "Pebble watch package",
         license: "BSD-3-Clause",
         latest_version: "2.0.0",
         versions: ["2.0.0"],
         exposed_modules: [],
         elm_json: %{}
       }}
    end

    def package_details("elm-pebble/companion-internal", _opts) do
      {:ok,
       %{
         name: "elm-pebble/companion-internal",
         summary: "Source-backed companion modules",
         license: "BSD-3-Clause",
         latest_version: "latest",
         versions: ["latest"],
         exposed_modules: [],
         elm_json: %{}
       }}
    end

    def package_details(package, _opts) do
      {:ok,
       %{
         name: package,
         summary: "Summary for #{package}",
         license: "BSD-3-Clause",
         latest_version: "2.0.0",
         versions: ["1.0.0", "2.0.0"],
         exposed_modules: ["Http"],
         elm_json: %{}
       }}
    end

    @impl true
    def versions("elm/http", _opts), do: {:ok, ["2.0.0"]}
    def versions("elm/html", _opts), do: {:ok, ["2.0.0"]}
    def versions("elm/virtual-dom", _opts), do: {:ok, ["1.0.3"]}
    def versions("elm/url", _opts), do: {:ok, ["1.0.0"]}
    def versions("elm-pebble/elm-watch", _opts), do: {:ok, ["1.0.0", "2.0.0"]}
    def versions("elm/core", _opts), do: {:ok, ["1.0.5"]}
    def versions("elm/json", _opts), do: {:ok, ["1.1.3"]}
    def versions(_package, _opts), do: {:ok, ["1.0.0"]}

    @impl true
    def package_release("elm/http", "2.0.0", _opts) do
      {:ok,
       %{
         "dependencies" => %{
           "elm/core" => "1.0.0 <= v < 2.0.0",
           "elm/url" => "1.0.0 <= v < 2.0.0"
         }
       }}
    end

    def package_release("elm/html", "2.0.0", _opts) do
      {:ok,
       %{
         "dependencies" => %{
           "elm/core" => "1.0.0 <= v < 2.0.0",
           "elm/virtual-dom" => "1.0.0 <= v < 2.0.0"
         }
       }}
    end

    def package_release("elm/virtual-dom", "1.0.3", _opts) do
      {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}
    end

    def package_release("elm/url", "1.0.0", _opts) do
      {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}
    end

    def package_release("elm-pebble/elm-watch", version, _opts)
        when version in ["1.0.0", "2.0.0"] do
      {:ok,
       %{
         "dependencies" => %{
           "elm/core" => "1.0.0 <= v < 2.0.0",
           "elm/json" => "1.0.0 <= v < 2.0.0"
         }
       }}
    end

    def package_release("elm/core", "1.0.5", _opts), do: {:ok, %{"dependencies" => %{}}}

    def package_release("elm/json", "1.1.3", _opts),
      do: {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}

    def package_release(_package, _version, _opts), do: {:ok, %{"dependencies" => %{}}}

    @impl true
    def readme(package, version, _opts), do: {:ok, "# #{package} #{version}"}
  end

  setup do
    previous_packages_env = Application.get_env(:ide, Ide.Packages)

    Application.put_env(:ide, Ide.Packages,
      provider_order: [:mock],
      providers: [mock: [module: MockProvider]]
    )

    on_exit(fn ->
      if previous_packages_env == nil do
        Application.delete_env(:ide, Ide.Packages)
      else
        Application.put_env(:ide, Ide.Packages, previous_packages_env)
      end
    end)

    :ok
  end

  test "search/details/readme use configured provider" do
    assert {:ok, %{source: "mock", total: 1, packages: [pkg]}} = Packages.search("elm/http")
    assert pkg.name == "elm/http"
    assert pkg.compatibility.status == "blocked"
    assert pkg.compatibility.reason_code == "blocked_runtime_family"

    assert {:ok, %{name: "elm/http", source: "mock", compatibility: compatibility}} =
             Packages.package_details("elm/http")

    assert compatibility.status == "blocked"
    assert compatibility.reason_code == "blocked_runtime_family"

    assert {:ok, %{compatibility: phone_compatibility}} =
             Packages.package_details("elm/http", source: "mock", platform_target: :phone)

    assert phone_compatibility.status == "supported"

    assert Packages.compatibility_for_package("elm/random", platform_target: :phone).status ==
             "supported"

    assert Packages.compatibility_for_package("elm-pebble/elm-watch", platform_target: :phone).status ==
             "blocked"

    assert Packages.compatibility_for_package("elm/core").status == "supported"

    assert {:ok, %{versions: ["2.0.0"]}} = Packages.versions("elm/http")
    assert {:ok, %{readme: "# elm/http latest"}} = Packages.readme("elm/http")
  end

  test "search does not apply watch compatibility filtering for phone target" do
    assert {:ok, %{total: 0, packages: []}} = Packages.search("elm/html", source: "mock")

    assert {:ok, %{total: total, packages: [pkg]}} =
             Packages.search("elm/html", source: "mock", platform_target: :phone)

    assert total == 1
    assert pkg.name == "elm/html"
    assert pkg.compatibility.status == "supported"
  end

  test "add_to_project writes dependency to elm.json" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "PackagesService",
               "slug" => "packages-service",
               "target_type" => "app"
             })

    assert {:ok, result} =
             Packages.add_to_project(project, "elm/http", source_root: "watch", source: "mock")

    assert result.package == "elm/http"
    assert result.selected_version == "2.0.0"

    assert result.project.package_metadata_cache["packages"]["elm/http"]["exposed_modules"] == [
             "Http"
           ]

    assert {:ok, content} = Projects.read_source_file(project, "watch", "elm.json")
    assert {:ok, decoded} = Jason.decode(content)
    assert decoded["dependencies"]["direct"]["elm/http"] == "2.0.0"
    assert decoded["dependencies"]["indirect"]["elm/url"] == "1.0.0"
  end

  test "remove_from_project drops direct dep and recomputes indirect" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "PackagesRm",
               "slug" => "packages-rm-service",
               "target_type" => "app"
             })

    assert {:ok, _} =
             Packages.add_to_project(project, "elm/http", source_root: "watch", source: "mock")

    assert {:ok, _} =
             Packages.remove_from_project(project, "elm/http",
               source_root: "watch",
               source: "mock"
             )

    assert {:ok, content} = Projects.read_source_file(project, "watch", "elm.json")
    assert {:ok, decoded} = Jason.decode(content)
    refute Map.has_key?(decoded["dependencies"]["direct"], "elm/http")
    refute Map.has_key?(decoded["dependencies"]["indirect"], "elm/url")
  end

  test "remove_from_project rejects built-in platform packages" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "PackagesBuiltin",
               "slug" => "packages-builtin-service",
               "target_type" => "app"
             })

    assert {:error, :builtin_package_not_removable} =
             Packages.remove_from_project(project, "elm-pebble/elm-watch",
               source_root: "watch",
               source: "mock"
             )

    assert {:error, :builtin_package_not_removable} =
             Packages.remove_from_project(project, "elm/core",
               source_root: "watch",
               source: "mock"
             )

    assert {:error, :builtin_package_not_removable} =
             Packages.remove_from_project(project, "elm/json",
               source_root: "watch",
               source: "mock"
             )

    assert {:error, :builtin_package_not_removable} =
             Packages.remove_from_project(project, "elm/time",
               source_root: "watch",
               source: "mock"
             )

    assert {:ok, _} =
             Packages.add_to_project(project, "elm/random",
               source_root: "phone",
               source: "mock"
             )

    assert {:ok, _} =
             Packages.remove_from_project(project, "elm/random",
               source_root: "phone",
               source: "mock"
             )
  end

  test "remove_from_project rejects packages imported by source files" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "PackagesUsed",
               "slug" => "packages-used-service",
               "target_type" => "app",
               "template" => "game-2048"
             })

    assert {:error, {:package_in_use, "elm/random"}} =
             Packages.remove_from_project(project, "elm/random",
               source_root: "watch",
               source: "mock"
             )
  end

  test "package_usage uses cached exposed modules before provider package details" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "PackagesMetadataCache",
               "slug" => "packages-metadata-cache",
               "target_type" => "app"
             })

    assert {:ok, content} = Projects.read_source_file(project, "watch", "elm.json")
    assert {:ok, decoded} = Jason.decode(content)

    updated =
      put_in(decoded, ["dependencies", "direct", "elm/no-details"], "1.0.0")

    assert :ok =
             Projects.write_source_file(
               project,
               "watch",
               "elm.json",
               Jason.encode!(updated, pretty: true) <> "\n"
             )

    assert :ok =
             Projects.write_source_file(
               project,
               "watch",
               "src/UsesCachedModule.elm",
               """
               module UsesCachedModule exposing (value)

               import Cached.Module

               value : Int
               value =
                   1
               """
             )

    assert {:ok, project} =
             Projects.update_project(project, %{
               "package_metadata_cache" => %{
                 "schema_version" => 1,
                 "packages" => %{
                   "elm/no-details" => %{
                     "version" => "1.0.0",
                     "exposed_modules" => ["Cached.Module"]
                   }
                 }
               }
             })

    assert %{"elm/no-details" => true} =
             Packages.package_usage(project, ["elm/no-details"],
               source_root: "watch",
               source: "mock"
             )
  end

  test "list_doc_package_rows includes source-backed Pebble modules when provider lacks exposed modules" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "PackagesDocRows",
               "slug" => "packages-doc-rows",
               "target_type" => "app"
             })

    assert {:ok, rows} =
             Packages.list_doc_package_rows(project, source_root: "watch", source: "mock")

    pebble = Enum.find(rows, &(&1.package == "elm-pebble/elm-watch"))
    assert pebble
    assert "Pebble.Cmd" in pebble.modules
    assert "Pebble.Platform" in pebble.modules
  end

  test "list_doc_package_rows includes companion packages for phone target" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "PackagesDocRowsPhone",
               "slug" => "packages-doc-rows-phone",
               "target_type" => "app"
             })

    assert {:ok, rows} =
             Packages.list_doc_package_rows(project,
               source_root: "phone",
               source: "mock",
               platform_target: :phone
             )

    refute Enum.any?(rows, &(&1.package == "elm-pebble/elm-phone"))

    companion_internal = Enum.find(rows, &(&1.package == "elm-pebble/companion-internal"))
    assert companion_internal
    assert "Companion.Phone" in companion_internal.modules

    companion_protocol = Enum.find(rows, &(&1.package == "elm-pebble/companion-protocol"))
    assert companion_protocol
    assert "Companion.Watch" in companion_protocol.modules

    companion_core = Enum.find(rows, &(&1.package == "elm-pebble/companion-core"))
    assert companion_core
    refute "Pebble.Companion.AppMessage" in companion_core.modules
    assert "Pebble.Companion.Command" in companion_core.modules

    companion_preferences = Enum.find(rows, &(&1.package == "elm-pebble/companion-preferences"))
    assert companion_preferences
    assert "Pebble.Companion.Preferences" in companion_preferences.modules
  end
end
