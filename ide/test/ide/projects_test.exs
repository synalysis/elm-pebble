defmodule Ide.ProjectsTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger
  alias Ide.Debugger.AppMessageQueue
  alias Ide.Auth.User
  alias Ide.Projects
  alias Ide.Projects.Project

  setup do
    import Ecto.Query

    root = Path.join(System.tmp_dir!(), "ide_projects_test_#{System.unique_integer([:positive])}")
    Application.put_env(:ide, Ide.Projects, projects_root: root)
    Ide.Repo.delete_all(Project)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "create/list/activate project" do
    assert {:ok, first} =
             Projects.create_project(%{
               "name" => "Alpha",
               "slug" => "alpha",
               "target_type" => "app"
             })

    assert first.active

    assert {:ok, second} =
             Projects.create_project(%{
               "name" => "Beta",
               "slug" => "beta",
               "target_type" => "watchface"
             })

    refute second.active
    assert Enum.map(Projects.list_projects(), & &1.slug) == ["alpha", "beta"]

    assert {:ok, _} = Projects.activate_project(second)
    assert Projects.active_project().slug == "beta"
  end

  test "create_project returns changeset error when slug already exists" do
    assert {:ok, _project} =
             Projects.create_project(%{
               "name" => "Digital",
               "slug" => "digital",
               "target_type" => "watchface",
               "template" => "watchface-digital"
             })

    assert {:error, changeset} =
             Projects.create_project(%{
               "name" => "Digital Again",
               "slug" => "digital",
               "target_type" => "watchface",
               "template" => "watchface-digital"
             })

    assert %{slug: ["is already in use. Choose a different slug."]} = errors_on(changeset)
  end

  test "failed create removes workspace directories" do
    slug = "bootstrap-failure-#{System.unique_integer([:positive])}"
    fake_priv = Path.join(System.tmp_dir!(), "ide_fake_priv_#{System.unique_integer([:positive])}")
    templates_dir = Path.join(fake_priv, "project_templates")
    File.mkdir_p!(templates_dir)

    prev_paths_config = Application.get_env(:ide, Ide.Paths, [])

    on_exit(fn ->
      Application.put_env(:ide, Ide.Paths, prev_paths_config)
      File.rm_rf(fake_priv)
    end)

    Application.put_env(:ide, Ide.Paths, Keyword.put(prev_paths_config, :priv_dir, fake_priv))

    assert {:error, {:missing_template_asset, missing_path}} =
             Projects.create_project(%{
               "name" => "Bootstrap Failure",
               "slug" => slug,
               "target_type" => "app"
             })

    assert missing_path =~ "starter_watch"

    workspace = Path.join(Projects.projects_root(), slug)
    refute File.exists?(workspace)
    refute Projects.get_project_by_slug(slug)
  end

  test "project ownership scopes slugs and workspaces" do
    {:ok, alice} =
      %User{}
      |> User.changeset(%{firebase_uid: "alice"})
      |> Repo.insert()

    {:ok, bob} =
      %User{}
      |> User.changeset(%{firebase_uid: "bob"})
      |> Repo.insert()

    assert {:ok, alice_project} =
             Projects.create_project(
               %{"name" => "Shared", "slug" => "shared", "target_type" => "app"},
               alice
             )

    assert {:ok, bob_project} =
             Projects.create_project(
               %{"name" => "Shared", "slug" => "shared", "target_type" => "app"},
               bob
             )

    assert Projects.get_project_by_slug("shared", alice).id == alice_project.id
    assert Projects.get_project_by_slug("shared", bob).id == bob_project.id
    assert Enum.map(Projects.list_projects(alice), & &1.id) == [alice_project.id]
    assert Enum.map(Projects.list_projects(bob), & &1.id) == [bob_project.id]

    assert Projects.project_workspace_path(alice_project) =~ "/users/#{alice.id}/shared"
    assert Projects.project_workspace_path(bob_project) =~ "/users/#{bob.id}/shared"

    assert Projects.scope_key(alice_project) == "users/#{alice.id}/shared"
    assert Projects.scope_key(bob_project) == "users/#{bob.id}/shared"
    refute Projects.scope_key(alice_project) == Projects.scope_key(bob_project)

    Process.put(:ide_current_user, alice)

    try do
      assert Projects.get_project_by_slug("shared").id == alice_project.id
      assert Enum.map(Projects.list_projects(), & &1.id) == [alice_project.id]
    after
      Process.delete(:ide_current_user)
    end
  end

  test "owned project adopts legacy unscoped workspace files" do
    {:ok, user} =
      %User{}
      |> User.changeset(%{firebase_uid: "legacy-owner"})
      |> Repo.insert()

    slug = "legacy-adopt-#{System.unique_integer([:positive])}"
    legacy = Path.join(Projects.projects_root(), slug)
    on_exit(fn -> File.rm_rf(legacy) end)

    assert {:ok, project} =
             Projects.create_project(
               %{"name" => "Legacy Adopt", "slug" => slug, "target_type" => "app"},
               user
             )

    scoped = Projects.project_workspace_path(project)
    on_exit(fn -> File.rm_rf(scoped) end)

    File.rm_rf!(scoped)
    File.mkdir_p!(Path.join(legacy, "watch/src"))
    File.write!(Path.join(legacy, "watch/elm.json"), ~s({"type":"application"}))
    File.write!(Path.join(legacy, "watch/src/Main.elm"), "module Main exposing (main)")

    assert Projects.project_workspace_path(project) == scoped
    assert File.exists?(Path.join(scoped, "watch/elm.json"))
    assert File.exists?(Path.join(scoped, "watch/src/Main.elm"))
  end

  test "ensure_compiler_workspace recreates missing watch elm.json" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Repair Elm Json",
               "slug" => "repair-elm-json-#{System.unique_integer([:positive])}",
               "target_type" => "app"
             })

    base = Projects.project_workspace_path(project)
    on_exit(fn -> File.rm_rf(base) end)

    File.rm!(Path.join(base, "watch/elm.json"))
    refute File.exists?(Path.join(base, "watch/elm.json"))

    assert :ok = Projects.ensure_compiler_workspace(project)
    assert File.exists?(Path.join(base, "watch/elm.json"))

    assert {:ok, result} =
             Ide.Compiler.compile(project.slug,
               workspace_root: Path.join(base, "watch"),
               source_roots: project.source_roots
             )

    assert result.status == :ok
  end

  test "package_for_emulator_session repairs missing watch elm.json before packaging" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Emulator Package Repair",
               "slug" => "emulator-package-repair-#{System.unique_integer([:positive])}",
               "target_type" => "watchface"
             })

    workspace_root = Projects.project_workspace_path(project)
    on_exit(fn -> File.rm_rf(workspace_root) end)

    File.rm!(Path.join(workspace_root, "watch/elm.json"))
    refute File.exists?(Path.join(workspace_root, "watch/elm.json"))

    assert :ok = Projects.ensure_compiler_workspace(project)
    assert File.exists?(Path.join(workspace_root, "watch/elm.json"))
    assert Ide.Compiler.resolve_elm_project_dir(workspace_root, project.source_roots)
  end

  test "ensure_packagable_workspace does not restore a missing workspace from template" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Packagable Repair",
               "slug" => "packagable-repair-#{System.unique_integer([:positive])}",
               "target_type" => "watchface",
               "template" => "watchface-digital"
             })

    workspace_root = Projects.project_workspace_path(project)
    on_exit(fn -> File.rm_rf(workspace_root) end)

    for root <- ["watch", "protocol", "phone"] do
      path = Path.join(workspace_root, root)
      if File.exists?(path), do: File.rm_rf!(path)
    end

    refute Ide.Projects.FileStore.workspace_has_elm_roots?(workspace_root)

    assert {:error, :compile_project_root_not_found} =
             Projects.ensure_packagable_workspace(project)

    refute File.exists?(Path.join(workspace_root, "watch/src/Main.elm"))
  end

  test "source file operations across roots" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Ops",
               "slug" => "ops",
               "target_type" => "app",
               "source_roots" => ["watch", "protocol", "phone"]
             })

    assert :ok =
             Projects.write_source_file(
               project,
               "watch",
               "src/Main.elm",
               "module Main exposing (main)"
             )

    assert {:ok, "module Main exposing (main)"} =
             Projects.read_source_file(project, "watch", "src/Main.elm")

    assert :ok = Projects.rename_source_path(project, "watch", "src/Main.elm", "src/App.elm")
    assert {:ok, _} = Projects.read_source_file(project, "watch", "src/App.elm")

    assert :ok = Projects.delete_source_path(project, "watch", "src/App.elm")
    assert {:error, :enoent} = Projects.read_source_file(project, "watch", "src/App.elm")
  end

  test "delete project clears debugger state for reusable slug" do
    slug = "delete-clears-debugger-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "DeleteClearsDebugger",
               "slug" => slug,
               "target_type" => "app"
             })

    assert {:ok, started} = Debugger.start_session(slug)
    assert started.running == true
    assert started.events != []

    assert {:ok, _deleted} = Projects.delete_project(project)

    assert {:ok, snapshot} = Debugger.snapshot(slug, event_limit: 10)
    assert snapshot.running == false
    assert snapshot.events == []
    assert snapshot.debugger_timeline == []
  end

  test "bitmap/font resource import generates read-only resources module" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "BitmapOps",
               "slug" => "bitmap-ops-#{System.unique_integer([:positive])}",
               "target_type" => "app",
               "release_defaults" => %{"target_platforms" => ["basalt", "chalk"]}
             })

    tmp_png = write_test_bitmap_png()
    on_exit(fn -> File.rm(tmp_png) end)

    tmp_ttf =
      Path.join(System.tmp_dir!(), "font_upload_#{System.unique_integer([:positive])}.ttf")

    File.write!(tmp_ttf, <<0, 1, 0, 0, 0, 14, 0, 128>>)
    on_exit(fn -> File.rm(tmp_ttf) end)

    tmp_pdc =
      Path.join(System.tmp_dir!(), "vector_upload_#{System.unique_integer([:positive])}.pdc")

    File.write!(
      tmp_pdc,
      <<0x50, 0x44, 0x43, 0x49, 0x1D, 0x00, 0x00, 0x00, 0x01, 0x00, 0x14, 0x00, 0x14, 0x00, 0x01,
        0x00, 0x01, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x03, 0x00, 0x02, 0x00, 0x12, 0x00, 0x0A,
        0x00, 0x02, 0x00, 0x12, 0x00, 0x02, 0x00>>
    )

    on_exit(fn -> File.rm(tmp_pdc) end)

    assert {:ok, _} = Projects.import_bitmap_resource(project, tmp_png, "logo.png")
    assert {:ok, _} = Projects.import_font_resource(project, tmp_ttf, "menu.ttf")

    assert {:ok, %{duplicate: true}} =
             Projects.import_bitmap_resource(project, tmp_png, "logo-copy.png")

    assert {:ok, %{duplicate: true}} =
             Projects.import_font_resource(project, tmp_ttf, "menu-copy.ttf")

    assert {:ok, entries} = Projects.list_bitmap_resources(project)
    assert [%{ctor: "BitmapStaticLogo"}] = entries
    assert {:ok, font_sources} = Projects.list_font_sources(project)
    assert [%{id: source_id, filename: "menu.ttf"}] = font_sources

    source_font_path =
      Path.join(Projects.project_workspace_path(project), "watch/resources/fonts/menu.ttf")

    assert File.exists?(source_font_path)

    assert {:ok, _} =
             Projects.add_font_variant(project, %{
               "source_id" => source_id,
               "ctor" => "MenuDigits28",
               "name" => "Menu Digits 28",
               "height" => "28",
               "characters" => "[0-9:.]",
               "tracking_adjust" => "1",
               "compatibility" => "2.7",
               "target_platforms" => "basalt chalk"
             })

    assert {:ok, _} =
             Projects.add_font_variant(project, %{
               "source_id" => source_id,
               "ctor" => "MenuText18",
               "name" => "Menu Text 18",
               "height" => "18",
               "characters" => "[A-Za-z ]",
               "tracking_adjust" => "0",
               "compatibility" => "3.0"
             })

    assert {:ok, font_entries} = Projects.list_font_resources(project)
    assert Enum.map(font_entries, & &1.ctor) == ["MenuDigits28", "MenuText18"]

    assert {:ok, _} = Projects.add_font_variant(project, %{"source_id" => source_id})
    assert {:ok, font_entries} = Projects.list_font_resources(project)
    auto_entry = Enum.find(font_entries, &(&1.ctor == "Menu"))
    assert auto_entry.height == 29
    assert auto_entry.compatibility == "latest"
    assert auto_entry.target_platforms == ["basalt", "chalk"]

    generated =
      Path.join(Projects.project_workspace_path(project), "watch/src/Pebble/Ui/Resources.elm")

    assert {:ok, source} = File.read(generated)
    assert String.contains?(source, "Generated from the resources configured")
    assert String.contains?(source, "project settings Resources page")
    assert String.contains?(source, "type StaticBitmap")
    assert String.contains?(source, "Logo")
    assert String.contains?(source, "type alias StaticBitmapInfo")
    assert String.contains?(source, "staticBitmapInfo")
    assert String.contains?(source, "type Font")
    assert String.contains?(source, "Menu")
    assert String.contains?(source, "MenuDigits28")
    assert String.contains?(source, "MenuText18")
    assert String.contains?(source, "height = 28")
    assert String.contains?(source, "height = 18")
    assert String.contains?(source, "type alias FontInfo")
    assert String.contains?(source, "fontInfo")
    refute String.contains?(source, "toResourceId")

    assert {:ok, _} = Projects.delete_bitmap_resource(project, "BitmapStaticLogo")
    assert {:ok, []} = Projects.list_bitmap_resources(project)

    assert {:ok, _} =
             Projects.import_vector_resource(project, tmp_pdc, "piece.pdc")

    assert {:ok, vector_entries} = Projects.list_vector_resources(project)
    assert [%{ctor: "VectorStaticPiece"}] = vector_entries

    svg_path =
      Path.join(System.tmp_dir!(), "vector_upload_#{System.unique_integer([:positive])}.svg")

    File.write!(
      svg_path,
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><polygon points="2,18 10,2 18,18" fill="#000000"/></svg>)
    )

    on_exit(fn -> File.rm(svg_path) end)

    assert {:ok, _} = Projects.import_vector_resource(project, svg_path, "tri.svg")
    assert {:ok, vector_entries} = Projects.list_vector_resources(project)
    assert Enum.any?(vector_entries, &(&1.ctor == "VectorStaticTri"))

    assert String.contains?(File.read!(generated), "type StaticVector")
    assert String.contains?(File.read!(generated), "drawVectorAt") == false

    assert {:ok, _} = Projects.delete_vector_resource(project, "VectorStaticPiece")
    assert {:ok, _} = Projects.delete_font_resource(project, "MenuDigits28")
    assert File.exists?(source_font_path)
    assert {:ok, remaining_fonts} = Projects.list_font_resources(project)
    assert Enum.map(remaining_fonts, & &1.ctor) == ["Menu", "MenuText18"]
    assert {:ok, _} = Projects.delete_font_source(project, source_id)
    refute File.exists?(source_font_path)
    assert {:ok, []} = Projects.list_font_resources(project)
    assert {:ok, []} = Projects.list_font_sources(project)
  end

  test "game templates seed app projects with Elm game APIs" do
    for template <- ["game-basic", "game-tiny-bird", "game-jump-n-run", "game-2048", "game-elmtris"] do
      slug = "#{template}-#{System.unique_integer([:positive])}"

      assert {:ok, project} =
               Projects.create_project(%{
                 "name" => template,
                 "slug" => slug,
                 "target_type" => "watchface",
                 "template" => template
               })

      assert project.target_type == "app"
      base = Projects.project_workspace_path(project)
      assert File.exists?(Path.join(base, "watch/src/Main.elm"))
      assert {:ok, main} = File.read(Path.join(base, "watch/src/Main.elm"))
      assert String.contains?(main, "Pebble.Frame") or String.contains?(main, "Pebble.Button")
    end
  end

  test "watch demo templates seed watch-only apps for Tier 1 Pebble APIs" do
    demos = [
      {"watch-demo-accel", "Pebble.Accel", "app"},
      {"watch-demo-vibes", "Vibes.pattern", "app"},
      {"watch-demo-data-log", "Pebble.DataLog", "app"},
      {"watch-demo-app-focus", "Pebble.AppFocus", "app"},
      {"watch-demo-compass", "Pebble.Compass", "app"},
      {"watch-demo-dictation", "Pebble.Dictation", "app"},
      {"watch-demo-health", "Pebble.Health", "app"},
      {"watch-demo-light", "Light.onChange", "app"},
      {"watch-demo-watch-info", "Pebble.WatchInfo", "app"},
      {"watch-demo-speaker", "Pebble.Speaker", "app"},
      {"watch-demo-storage", "Pebble.Storage", "app"},
      {"watch-demo-launch", "quickLaunchAction", "app"},
      {"watch-demo-screen-change", "onScreenChange", "app"},
      {"watch-demo-system", "Pebble.System", "app"},
      {"watch-demo-unobstructed", "Pebble.UnobstructedArea", "app"},
      {"watch-demo-wakeup", "Pebble.Wakeup", "app"},
      {"watch-demo-frame", "Pebble.Frame", "app"},
      {"watch-demo-time", "Pebble.Time", "app"},
      {"watch-demo-log", "Pebble.Log", "app"}
    ]

    for {template, snippet, target_type} <- demos do
      slug = "#{template}-#{System.unique_integer([:positive])}"

      assert {:ok, project} =
               Projects.create_project(%{
                 "name" => "Demo #{template}",
                 "slug" => slug,
                 "target_type" => target_type,
                 "template" => template
               })

      base = Projects.project_workspace_path(project)
      assert project.target_type == target_type
      assert File.exists?(Path.join(base, "watch/src/Main.elm"))
      refute File.exists?(Path.join(base, "phone/src/CompanionApp.elm"))

      assert {:ok, main} = File.read(Path.join(base, "watch/src/Main.elm"))
      assert String.contains?(main, snippet)
    end
  end

  test "starter watch template only places user sources under watch/src" do
    slug = "starter-clean-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "StarterClean",
               "slug" => slug,
               "target_type" => "app",
               "template" => "starter"
             })

    base = Projects.project_workspace_path(project)
    watch_src = Path.join(base, "watch/src")

    assert File.exists?(Path.join(watch_src, "Main.elm"))
    refute File.exists?(Path.join(watch_src, "CoreCompliance.elm"))
    assert File.exists?(Path.join(watch_src, "Pebble/Ui/Resources.elm"))

    assert {:ok, elm_json_raw} = File.read(Path.join(base, "watch/elm.json"))
    assert {:ok, decoded} = Jason.decode(elm_json_raw)
    dirs = Map.fetch!(decoded, "source-directories")
    direct = get_in(decoded, ["dependencies", "direct"]) || %{}
    assert "src" in dirs
    assert Enum.any?(dirs, &(&1 == Ide.InternalPackages.pebble_elm_src_abs()))

    assert "../protocol/src" in dirs

    refute Map.has_key?(direct, "elm-pebble/elm-watch")
    assert Map.fetch!(direct, "elm/json") == "1.1.3"

    assert File.exists?(Path.join(base, "protocol/elm.json"))
    assert File.exists?(Path.join(base, "phone/elm.json"))

    assert {:ok, phone_elm_json_raw} = File.read(Path.join(base, "phone/elm.json"))
    assert {:ok, phone_decoded} = Jason.decode(phone_elm_json_raw)
    phone_direct = get_in(phone_decoded, ["dependencies", "direct"]) || %{}
    assert phone_direct["elm/http"] == "2.0.0"
    refute Map.has_key?(phone_direct, "elm/random")

    refute Map.has_key?(
             phone_direct,
             "elm-pebble/elm-phone"
           )

    phone_dirs = Map.fetch!(phone_decoded, "source-directories")
    assert "../protocol/src" in phone_dirs
    refute Enum.any?(phone_dirs, &String.ends_with?(&1, "phone-pebble-stubs/src"))
    refute Enum.any?(phone_dirs, &String.ends_with?(&1, "shared/elm-companion"))

    assert Enum.any?(
             phone_dirs,
             &(&1 == Ide.InternalPackages.pebble_companion_core_elm_src_abs())
           )

    assert Enum.any?(
             phone_dirs,
             &(&1 == Ide.InternalPackages.pebble_companion_preferences_elm_src_abs())
           )

    refute Enum.any?(phone_dirs, &String.ends_with?(&1, "internal_packages/elm-random/src"))

    assert {:ok, protocol_types} =
             Projects.read_source_file(project, "protocol", "src/Companion/Types.elm")

    assert String.contains?(protocol_types, "module Companion.Types")

    assert {:ok, phone_engine} = Projects.read_source_file(project, "phone", "src/Engine.elm")
    assert String.contains?(phone_engine, "module Engine")
  end

  test "phone tree hides platform bridge modules that should be browsed through docs" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "PhoneTreeDocs",
               "slug" => "phone-tree-docs-#{System.unique_integer([:positive])}",
               "target_type" => "app",
               "template" => "starter"
             })

    assert {:error, _} =
             Projects.read_source_file(project, "phone", "src/Pebble/Companion/AppMessage.elm")

    phone_tree =
      project
      |> Projects.list_source_tree()
      |> Enum.find(&(&1.source_root == "phone"))

    refute "src/Pebble/Companion/AppMessage.elm" in tree_rel_paths(phone_tree.nodes)
    refute "src/Companion/Internal.elm" in tree_rel_paths(phone_tree.nodes)
    refute "src/Engine.elm" in tree_rel_paths(phone_tree.nodes)
  end

  test "protocol tree hides platform bridge modules that should be browsed through docs" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ProtocolTreeDocs",
               "slug" => "protocol-tree-docs-#{System.unique_integer([:positive])}",
               "target_type" => "app",
               "template" => "starter"
             })

    assert {:ok, watch_bridge} =
             Projects.read_source_file(project, "protocol", "src/Companion/Watch.elm")

    assert String.contains?(watch_bridge, "module Companion.Watch")

    protocol_tree =
      project
      |> Projects.list_source_tree()
      |> Enum.find(&(&1.source_root == "protocol"))

    refute "src/Companion/Watch.elm" in tree_rel_paths(protocol_tree.nodes)
    refute "src/Companion/Internal.elm" in tree_rel_paths(protocol_tree.nodes)
    assert "src/Companion/Types.elm" in tree_rel_paths(protocol_tree.nodes)
  end

  test "listing a companion project restores missing default protocol files" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ProtocolInvariant",
               "slug" => "protocol-invariant-#{System.unique_integer([:positive])}",
               "target_type" => "app",
               "template" => "starter"
             })

    base = Projects.project_workspace_path(project)
    File.rm_rf!(Path.join(base, "protocol"))

    refute File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))

    protocol_tree =
      project
      |> Projects.list_source_tree()
      |> Enum.find(&(&1.source_root == "protocol"))

    assert File.exists?(Path.join(base, "protocol/elm.json"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Internal.elm"))
    assert "src/Companion/Types.elm" in tree_rel_paths(protocol_tree.nodes)
  end

  test "watchface templates seed watch-only starter apps" do
    for {template, expected_line} <- [
          {"watchface-digital", "timeString"},
          {"watchface-analog", "handX"}
        ] do
      slug =
        "watchface-template-#{String.replace(template, "-", "_")}-#{System.unique_integer([:positive])}"

      assert {:ok, project} =
               Projects.create_project(%{
                 "name" => "WatchfaceTemplate",
                 "slug" => slug,
                 "target_type" => "app",
                 "template" => template
               })

      base = Projects.project_workspace_path(project)
      assert project.target_type == "watchface"
      assert File.exists?(Path.join(base, "watch/src/Main.elm"))
      assert File.exists?(Path.join(base, "watch/index.html"))
      refute File.exists?(Path.join(base, "protocol/elm.json"))
      refute File.exists?(Path.join(base, "phone/elm.json"))
      refute File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))
      refute File.exists?(Path.join(base, "phone/src/Engine.elm"))

      assert {:ok, watch_main} = Projects.read_source_file(project, "watch", "src/Main.elm")
      assert String.contains?(watch_main, expected_line)
      refute String.contains?(watch_main, "Companion")

      assert {:ok, watch_elm_json_raw} = File.read(Path.join(base, "watch/elm.json"))
      assert {:ok, watch_decoded} = Jason.decode(watch_elm_json_raw)
      watch_direct = get_in(watch_decoded, ["dependencies", "direct"]) || %{}
      assert Map.fetch!(watch_direct, "elm/json") == "1.1.3"
    end
  end

  test "add_companion_app scaffolds phone and protocol for watch-only projects" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "AddCompanion",
               "slug" => "add-companion-#{System.unique_integer([:positive])}",
               "target_type" => "app",
               "template" => "watchface-digital"
             })

    base = Projects.project_workspace_path(project)
    refute Projects.companion_app_present?(project)
    refute File.exists?(Path.join(base, "phone/elm.json"))
    refute File.exists?(Path.join(base, "protocol/elm.json"))

    assert :ok = Projects.add_companion_app(project)

    assert Projects.companion_app_present?(project)
    assert File.exists?(Path.join(base, "phone/elm.json"))
    assert File.exists?(Path.join(base, "phone/src/CompanionApp.elm"))
    assert File.exists?(Path.join(base, "protocol/elm.json"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Internal.elm"))

    assert {:ok, watch_elm_json_raw} = File.read(Path.join(base, "watch/elm.json"))
    assert {:ok, watch_decoded} = Jason.decode(watch_elm_json_raw)
    assert "../protocol/src" in Map.fetch!(watch_decoded, "source-directories")

    assert {:ok, phone_elm_json_raw} = File.read(Path.join(base, "phone/elm.json"))
    assert {:ok, phone_decoded} = Jason.decode(phone_elm_json_raw)
    phone_dirs = Map.fetch!(phone_decoded, "source-directories")
    refute Enum.any?(phone_dirs, &String.ends_with?(&1, "phone-pebble-stubs/src"))
    refute Enum.any?(phone_dirs, &String.ends_with?(&1, "shared/elm-companion"))

    assert Enum.any?(
             phone_dirs,
             &(&1 == Ide.InternalPackages.pebble_companion_core_elm_src_abs())
           )

    assert Enum.any?(
             phone_dirs,
             &(&1 == Ide.InternalPackages.pebble_companion_preferences_elm_src_abs())
           )

    refute Enum.any?(phone_dirs, &String.ends_with?(&1, "internal_packages/elm-random/src"))
    refute Map.has_key?(get_in(phone_decoded, ["dependencies", "direct"]) || %{}, "elm/random")
  end

  test "complete watchface tutorial template seeds sources and resources" do
    slug = "watchface-tutorial-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "WatchfaceTutorial",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-tutorial-complete"
             })

    base = Projects.project_workspace_path(project)
    assert project.target_type == "watchface"
    assert File.exists?(Path.join(base, "watch/src/Main.elm"))
    assert File.exists?(Path.join(base, "watch/resources/bitmaps/BitmapStaticBtIcon.png"))
    assert File.exists?(Path.join(base, "watch/resources/fonts/Jersey.ttf"))
    assert File.exists?(Path.join(base, "watch/resources/bitmaps.json"))
    assert File.exists?(Path.join(base, "watch/resources/fonts.json"))
    assert File.exists?(Path.join(base, "protocol/elm.json"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Internal.elm"))
    assert File.exists?(Path.join(base, "phone/elm.json"))
    assert File.exists?(Path.join(base, "phone/src/Engine.elm"))
    assert File.exists?(Path.join(base, "phone/src/CompanionApp.elm"))
    assert File.exists?(Path.join(base, "phone/src/CompanionPreferences.elm"))
    assert File.exists?(Path.join(base, "phone/src/Companion/GeneratedPreferences.elm"))
    refute File.exists?(Path.join(base, "phone/src/Pebble/Companion/AppMessage.elm"))
    refute File.exists?(Path.join(base, "phone/src/Companion/Internal.elm"))
    refute File.exists?(Path.join(base, "phone/src/Companion/Http.elm"))

    assert {:ok, watch_main} = Projects.read_source_file(project, "watch", "src/Main.elm")
    assert String.contains?(watch_main, "RequestWeather CurrentLocation")
    assert String.contains?(watch_main, "PebbleSystem.batteryLevel")
    assert String.contains?(watch_main, "PebbleUi.text")
    assert String.contains?(watch_main, "currentDateTime : Maybe PebbleTime.CurrentDateTime")
    assert String.contains?(watch_main, "temperature : Maybe Temperature")
    assert String.contains?(watch_main, "condition : Maybe WeatherCondition")
    refute String.contains?(watch_main, ", hour : Int")
    refute String.contains?(watch_main, ", dayOfWeek : PebbleTime.DayOfWeek")
    refute String.contains?(watch_main, "conditionCode")
    refute String.contains?(watch_main, "SetTemperatureUnit")
    refute String.contains?(watch_main, "| ProvideTemperature")
    refute String.contains?(watch_main, "| SetBackgroundColor")
    assert String.contains?(watch_main, "FromPhone PhoneToWatch")
    assert String.contains?(watch_main, "CompanionWatch.onPhoneToWatch FromPhone")

    assert {:ok, protocol_internal} =
             Projects.read_source_file(project, "protocol", "src/Companion/Internal.elm")

    assert String.contains?(protocol_internal, "Generated wire encoding and decoding helpers")
    assert String.contains?(protocol_internal, "encodeTemperatureTag")
    assert String.contains?(protocol_internal, "encodeTemperatureValue")
    assert String.contains?(protocol_internal, "encodeWeatherConditionCode")
    assert String.contains?(protocol_internal, "encodeTutorialColorCode")
    refute String.contains?(protocol_internal, "locationWeatherQuery")

    assert {:ok, resources} =
             Projects.read_source_file(project, "watch", "src/Pebble/Ui/Resources.elm")

    assert String.contains?(resources, "BitmapStaticBtIcon")
    assert String.contains?(resources, "Jersey")

    assert {:ok, watch_elm_json_raw} = File.read(Path.join(base, "watch/elm.json"))
    assert {:ok, watch_decoded} = Jason.decode(watch_elm_json_raw)
    assert get_in(watch_decoded, ["dependencies", "direct", "elm/json"]) == "1.1.3"

    assert {:ok, phone_elm_json_raw} = File.read(Path.join(base, "phone/elm.json"))
    assert {:ok, phone_decoded} = Jason.decode(phone_elm_json_raw)
    assert get_in(phone_decoded, ["dependencies", "direct", "elm/http"]) == "2.0.0"

    assert {:ok, companion_app} =
             Projects.read_source_file(project, "phone", "src/CompanionApp.elm")

    assert String.contains?(companion_app, "import Http")
    assert String.contains?(companion_app, "CompanionPhone.onWatchToPhone FromWatch")
    assert String.contains?(companion_app, "GeneratedPreferences.onConfiguration FromBridge")
    assert String.contains?(companion_app, "type alias Flags =")
    assert String.contains?(companion_app, "init : Flags -> ( Model, Cmd Msg )")
    assert String.contains?(companion_app, "GeneratedPreferences.decodeConfigurationFlags flags")
    assert String.contains?(companion_app, "sendSettings settings")

    assert String.contains?(
             companion_app,
             "FromBridge (Result String CompanionPreferences.Settings)"
           )

    assert String.contains?(companion_app, "FromBridge (Ok settings)")
    assert String.contains?(companion_app, "FromBridge (Err error)")
    assert String.contains?(companion_app, "errors : List String")
    assert String.contains?(companion_app, "addError")
    assert String.contains?(companion_app, "httpErrorToString")
    refute String.contains?(companion_app, "decodeConfigurationSaved")

    assert String.contains?(companion_app, "SetBackgroundColor settings.backgroundColor")
    assert String.contains?(companion_app, "SetTextColor settings.textColor")
    assert String.contains?(companion_app, "SetShowDate settings.showDate")
    assert String.contains?(companion_app, "FromWatch (Result String WatchToPhone)")
    assert String.contains?(companion_app, "conditionFromCode")
    assert String.contains?(companion_app, "ProvideCondition weather.condition")
    refute String.contains?(companion_app, "Companion.Http")
    refute String.contains?(companion_app, "port module")
    refute String.contains?(companion_app, "port incoming")
    refute String.contains?(companion_app, "port outgoing")
    refute String.contains?(companion_app, "port httpRequest")
    refute String.contains?(companion_app, "port httpResponse")

    assert {:ok, companion_preferences} =
             Projects.read_source_file(project, "phone", "src/CompanionPreferences.elm")

    assert String.contains?(companion_preferences, "Preferences.schema \"Tutorial Watchface\"")
    assert String.contains?(companion_preferences, "Preferences.field \"backgroundColor\"")
    assert String.contains?(companion_preferences, "Preferences.field \"textColor\"")
    assert String.contains?(companion_preferences, "Preferences.field \"showDate\"")

    assert {:ok, generated_preferences} =
             Projects.read_source_file(project, "phone", "src/Companion/GeneratedPreferences.elm")

    assert String.contains?(generated_preferences, "Subscribe to configuration responses")
    assert String.contains?(generated_preferences, "decodeConfigurationFlags flags")
    assert String.contains?(generated_preferences, "decodeConfigurationSaved")
    assert String.contains?(generated_preferences, "decodeConfigurationFlags")
    assert String.contains?(generated_preferences, "configurationFlagsDecoder")
    assert String.contains?(generated_preferences, "configurationResponseDecoder")
    assert String.contains?(generated_preferences, "preferencesErrorToString")

    assert String.contains?(
             generated_preferences,
             "Preferences.decodeResponse PreferencesSchema.settings"
           )

    assert {:ok, preferences_schema} = Ide.PebblePreferences.extract(Path.join(base, "phone"))
    assert preferences_schema.title == "Tutorial Watchface"

    assert Enum.flat_map(preferences_schema.sections, & &1.fields) |> Enum.map(& &1.id) == [
             "backgroundColor",
             "textColor",
             "showDate"
           ]
  end

  test "yes watchface template seeds watch protocol phone and preferences" do
    slug = "watchface-yes-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "YES Watchface",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-yes"
             })

    base = Projects.project_workspace_path(project)
    assert project.target_type == "watchface"
    assert File.exists?(Path.join(base, "watch/src/Main.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Watch.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Internal.elm"))
    assert File.exists?(Path.join(base, "phone/src/CompanionApp.elm"))
    assert File.exists?(Path.join(base, "phone/src/CompanionPreferences.elm"))
    assert File.exists?(Path.join(base, "phone/src/Companion/GeneratedPreferences.elm"))

    assert {:ok, watch_main} = Projects.read_source_file(project, "watch", "src/Main.elm")
    assert String.contains?(watch_main, "RequestUpdate")
    assert String.contains?(watch_main, "RequestSunData")
    assert String.contains?(watch_main, "RequestWeather")
    assert String.contains?(watch_main, "scheduleCompanionFetches")
    assert String.contains?(watch_main, "Render.face model.layout")
    assert String.contains?(watch_main, "ProvideSun")
    assert String.contains?(watch_main, "ProvideWeather")
    assert String.contains?(watch_main, "ProvideWind")
    assert String.contains?(watch_main, "ProvideTide")
    assert String.contains?(watch_main, "Button.onRelease Button.Down RequestRefresh")

    assert {:ok, yes_layout} = Projects.read_source_file(project, "watch", "src/Yes/Layout.elm")
    assert String.contains?(yes_layout, "fromScreen")
    assert String.contains?(yes_layout, "minDim // 2 - 22")

    assert {:ok, yes_render} = Projects.read_source_file(project, "watch", "src/Yes/Render.elm")
    assert String.contains?(yes_render, "pointAt layout.cx layout.cy layout.handLen handAngle")
    assert String.contains?(yes_render, "coloredRadialWedge")

    assert {:ok, protocol_types} =
             Projects.read_source_file(project, "protocol", "src/Companion/Types.elm")

    assert String.contains?(protocol_types, "type WeatherCondition")
    assert String.contains?(protocol_types, "ProvideTimezone Int")
    assert String.contains?(protocol_types, "PolarNight")
    assert String.contains?(protocol_types, "type Temperature")
    assert String.contains?(protocol_types, "type WindSpeed")
    assert String.contains?(protocol_types, "type Altitude")

    assert String.contains?(
             protocol_types,
             "ProvideWeather Temperature WeatherCondition Int Int Int"
           )

    assert String.contains?(protocol_types, "ProvideWind WindDirection WindSpeed")
    assert String.contains?(protocol_types, "ProvideAltitude Altitude")
    assert String.contains?(protocol_types, "SetCornerUpdateInterval Int")
    assert String.contains?(protocol_types, "RequestSunData")
    assert String.contains?(protocol_types, "RequestWeather")
    refute String.contains?(protocol_types, "SetUseInternet")
    refute String.contains?(protocol_types, "SetUnits")
    refute String.contains?(protocol_types, "InternetMode")

    assert {:ok, companion_app} =
             Projects.read_source_file(project, "phone", "src/CompanionApp.elm")

    assert String.contains?(companion_app, "CompanionPhone.onWatchToPhone FromWatch")
    assert String.contains?(companion_app, "FromWatch (Ok RequestSunData)")
    assert String.contains?(companion_app, "FromWatch (Ok RequestWeather)")

    assert String.contains?(
             companion_app,
             "GeneratedPreferences.onConfiguration FromConfiguration"
           )

    assert String.contains?(companion_app, "Geolocation.currentPosition")
    assert String.contains?(companion_app, "Geolocation.onCurrentPosition CurrentPosition")
    assert String.contains?(companion_app, "sunSnapshot location tzOffsetMin now")
    assert String.contains?(companion_app, "moonSnapshot location tzOffsetMin now")
    assert String.contains?(companion_app, "Weather.current")
    assert String.contains?(companion_app, "Environment.current")
    assert String.contains?(companion_app, "SetCornerUpdateInterval")
    refute String.contains?(companion_app, "ProvideAltitude")

    assert {:ok, companion_preferences} =
             Projects.read_source_file(project, "phone", "src/CompanionPreferences.elm")

    assert String.contains?(companion_preferences, "Preferences.schema \"YES Watchface\"")
    assert String.contains?(companion_preferences, "cornerUpdateInterval")
    refute String.contains?(companion_preferences, "Preferences.field \"homeLatitude\"")
    refute String.contains?(companion_preferences, "Preferences.field \"showTide\"")
    refute String.contains?(companion_preferences, "Preferences.choiceOption Fahrenheit")
    refute String.contains?(companion_preferences, "Preferences.choiceOption MilesPerHour")

    assert {:ok, preferences_schema} = Ide.PebblePreferences.extract(Path.join(base, "phone"))

    assert Enum.flat_map(preferences_schema.sections, & &1.fields) |> Enum.map(& &1.id) ==
             ["cornerUpdateInterval"]

    assert String.contains?(yes_render, "drawCorners")
    assert String.contains?(watch_main, "pickSlot")
    assert String.contains?(watch_main, "SetCornerUpdateInterval")
    assert String.contains?(watch_main, "Pebble.Health")
  end

  test "tangram time watchface template seeds watch protocol and phone" do
    slug = "watchface-tangram-time-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Tangram Time",
               "slug" => slug,
               "target_type" => "app",
               "template" => "watchface-tangram-time"
             })

    base = Projects.project_workspace_path(project)
    assert project.target_type == "watchface"
    assert File.exists?(Path.join(base, "watch/src/Main.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Watch.elm"))
    assert File.exists?(Path.join(base, "protocol/src/Companion/Internal.elm"))
    assert File.exists?(Path.join(base, "phone/src/CompanionApp.elm"))
    refute File.exists?(Path.join(base, "phone/src/CompanionPreferences.elm"))

    assert File.exists?(Path.join(base, "watch/resources/vectors.json"))
    assert File.exists?(Path.join(base, "watch/resources/vectors/VectorStaticTangramBird.pdc"))

    assert {:ok, watch_main} = Projects.read_source_file(project, "watch", "src/Main.elm")
    assert String.contains?(watch_main, "Ui.drawVectorAt")
    assert String.contains?(watch_main, "Resources.VectorStaticTangramBird")
    refute String.contains?(watch_main, "birdForm")
    assert String.contains?(watch_main, "CompanionWatch.sendWatchToPhone RequestFigure")
    assert String.contains?(watch_main, "BeginFigure figureId")
    assert String.contains?(watch_main, "downloadedTangram")
    assert String.contains?(watch_main, "Ui.toUiNode (tangramFaceOps model)")

    assert {:ok, protocol_types} =
             Projects.read_source_file(project, "protocol", "src/Companion/Types.elm")

    assert String.contains?(protocol_types, "ProvideFigure Int")

    assert String.contains?(protocol_types, "ProvidePiece Int (List Int)")

    assert String.contains?(protocol_types, "EndFigure Int")

    assert {:ok, protocol_internal} =
             Projects.read_source_file(project, "protocol", "src/Companion/Internal.elm")

    assert String.contains?(protocol_internal, "Generated wire encoding and decoding helpers")
    assert String.contains?(protocol_internal, "encodePhoneToWatch")
    assert String.contains?(protocol_internal, "decodeWatchToPhone")

    assert {:ok, companion_app} =
             Projects.read_source_file(project, "phone", "src/CompanionApp.elm")

    assert String.contains?(companion_app, "fetchCatalog")
    assert String.contains?(companion_app, "Time.every figureRotationInterval RotateFigure")
    assert String.contains?(companion_app, "sendFigureGeometry figureId pieces")

    assert {:ok, watch_elm_json_raw} = File.read(Path.join(base, "watch/elm.json"))
    assert {:ok, watch_decoded} = Jason.decode(watch_elm_json_raw)
    assert "../protocol/src" in Map.fetch!(watch_decoded, "source-directories")

    assert {:ok, phone_elm_json_raw} = File.read(Path.join(base, "phone/elm.json"))
    assert {:ok, phone_decoded} = Jason.decode(phone_elm_json_raw)
    assert "../protocol/src" in Map.fetch!(phone_decoded, "source-directories")
    assert get_in(phone_decoded, ["dependencies", "direct", "elm/http"]) == "2.0.0"
  end

  test "companion demo templates seed watch protocol and phone companion apps" do
    demos = [
      {"companion-demo-phone-status", "companion_demo_phone_status", "watchface",
       ["Pebble.Companion.Battery", "Sub.batch"]},
      {"companion-demo-weather-env", "companion_demo_weather_env", "watchface",
       ["Pebble.Companion.Weather", "Pebble.Companion.Environment"]},
      {"companion-demo-calendar", "companion_demo_calendar", "watchface",
       ["Pebble.Companion.Calendar", "ProvideNextEvent"]},
      {"companion-demo-storage", "companion_demo_storage", "app",
       ["Pebble.Companion.Storage", "Pebble.Companion.PreferenceStore"]},
      {"companion-demo-settings", "companion_demo_settings", "app",
       ["Pebble.Companion.Configuration", "Pebble.Companion.Lifecycle"]},
      {"companion-demo-geolocation", "companion_demo_geolocation", "watchface",
       ["Pebble.Companion.Geolocation", "ProvidePosition"]},
      {"companion-demo-websocket", "companion_demo_websocket", "app",
       ["Pebble.Companion.WebSocket", "Sub.batch"]},
      {"companion-demo-timeline", "companion_demo_timeline", "app",
       ["Pebble.Companion.Timeline", "Timeline.onToken"]}
    ]

    for {template, _dir, target_type, snippets} <- demos do
      slug = "#{template}-#{System.unique_integer([:positive])}"

      assert {:ok, project} =
               Projects.create_project(%{
                 "name" => "Demo #{template}",
                 "slug" => slug,
                 "target_type" => target_type,
                 "template" => template
               })

      base = Projects.project_workspace_path(project)
      assert project.target_type == target_type
      assert File.exists?(Path.join(base, "watch/src/Main.elm"))
      assert File.exists?(Path.join(base, "protocol/src/Companion/Types.elm"))
      assert File.exists?(Path.join(base, "protocol/src/Companion/Internal.elm"))
      assert File.exists?(Path.join(base, "phone/src/CompanionApp.elm"))

      assert {:ok, companion_app} =
               Projects.read_source_file(project, "phone", "src/CompanionApp.elm")

      for snippet <- snippets do
        assert String.contains?(companion_app, snippet)
      end

      assert {:ok, watch_elm_json_raw} = File.read(Path.join(base, "watch/elm.json"))
      assert {:ok, watch_decoded} = Jason.decode(watch_elm_json_raw)
      assert "../protocol/src" in Map.fetch!(watch_decoded, "source-directories")
    end
  end

  test "import project maps watch/protocol/phone directories" do
    source_root =
      Path.join(System.tmp_dir!(), "ide_import_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(source_root, "watch/src"))
    File.mkdir_p!(Path.join(source_root, "protocol/src/Companion"))
    File.mkdir_p!(Path.join(source_root, "phone/src"))
    File.write!(Path.join(source_root, "watch/src/Main.elm"), "module Main exposing (main)")

    File.write!(
      Path.join(source_root, "protocol/src/Companion/Types.elm"),
      "module Companion.Types exposing (..)"
    )

    File.write!(Path.join(source_root, "phone/src/Engine.elm"), "module Engine exposing (..)")

    on_exit(fn -> File.rm_rf(source_root) end)

    assert {:ok, project} =
             Projects.import_project(
               %{
                 "name" => "ImportedMulti",
                 "slug" => "imported-multi",
                 "target_type" => "app"
               },
               source_root
             )

    assert {:ok, _} = Projects.read_source_file(project, "watch", "src/Main.elm")

    assert {:ok, _} =
             Projects.read_source_file(project, "protocol", "src/Companion/Types.elm")

    assert {:ok, _} = Projects.read_source_file(project, "phone", "src/Engine.elm")
  end

  test "import project without roots falls back to watch root" do
    source_root =
      Path.join(System.tmp_dir!(), "ide_import_watch_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(source_root, "src"))
    File.write!(Path.join(source_root, "elm.json"), "{\"type\":\"application\"}")
    File.write!(Path.join(source_root, "src/Main.elm"), "module Main exposing (main)")

    on_exit(fn -> File.rm_rf(source_root) end)

    assert {:ok, project} =
             Projects.import_project(
               %{
                 "name" => "ImportedWatchOnly",
                 "slug" => "imported-watch-only",
                 "target_type" => "app"
               },
               source_root
             )

    assert {:ok, _} = Projects.read_source_file(project, "watch", "src/Main.elm")

    assert {:error, :enoent} =
             Projects.read_source_file(project, "protocol", "src/Companion/Types.elm")
  end

  test "import merge keeps existing watch sources when importing resources only" do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "ide_import_merge_workspace_#{System.unique_integer([:positive])}"
      )

    source_root =
      Path.join(
        System.tmp_dir!(),
        "ide_import_merge_source_#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      File.rm_rf(workspace)
      File.rm_rf(source_root)
    end)

    File.mkdir_p!(Path.join(workspace, "watch/src"))
    File.write!(Path.join(workspace, "watch/src/Main.elm"), "module Main exposing (main)")
    File.write!(Path.join(workspace, "watch/elm.json"), "{\"type\":\"application\"}")

    File.mkdir_p!(Path.join(source_root, "resources/bitmaps"))
    File.write!(Path.join(source_root, "resources/bitmaps/Extra.png"), <<137, 80, 78, 71>>)

    assert :ok = Ide.ProjectImport.import(source_root, workspace)

    assert File.exists?(Path.join(workspace, "watch/src/Main.elm"))
    assert File.exists?(Path.join(workspace, "watch/resources/bitmaps/Extra.png"))
  end

  test "delete_source_path refuses protected watch src tree" do
    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Protected Delete",
               "slug" => "protected-delete-#{System.unique_integer([:positive])}",
               "target_type" => "watchface",
               "template" => "watchface-digital"
             })

    assert {:error, :protected_path} = Projects.delete_source_path(project, "watch", "src")

    assert {:error, :protected_path} =
             Projects.delete_source_path(project, "watch", "src/Main.elm")

    assert {:ok, _} = Projects.read_source_file(project, "watch", "src/Main.elm")
  end

  test "legacy workspace is not adopted over scoped workspace with user artifacts" do
    slug = "legacy-artifacts-#{System.unique_integer([:positive])}"

    assert {:ok, user} =
             %User{}
             |> User.changeset(%{
               firebase_uid: "legacy-artifacts"
             })
             |> Repo.insert()

    legacy = Path.join(Projects.projects_root(), slug)
    on_exit(fn -> File.rm_rf(legacy) end)

    assert {:ok, project} =
             Projects.create_project(
               %{
                 "name" => "Legacy Artifacts",
                 "slug" => slug,
                 "target_type" => "watchface",
                 "template" => "watchface-digital"
               },
               user
             )

    scoped = Projects.project_workspace_path(project)
    assert scoped != legacy
    on_exit(fn -> File.rm_rf(scoped) end)

    File.rm_rf!(Path.join(scoped, "watch/src"))
    File.rm!(Path.join(scoped, "watch/elm.json"))
    File.mkdir_p!(Path.join(scoped, "watch/resources"))

    File.write!(
      Path.join(scoped, "watch/resources/bitmaps.json"),
      ~s({"schema_version":2,"entries":[]})
    )

    File.mkdir_p!(Path.join(legacy, "watch/src"))
    File.write!(Path.join(legacy, "watch/elm.json"), ~s({"type":"application"}))
    File.write!(Path.join(legacy, "watch/src/Main.elm"), "module Main exposing (main)")

    refute File.exists?(Path.join(scoped, "watch/src/Main.elm"))
    assert Projects.project_workspace_path(project) == scoped
    refute File.exists?(Path.join(scoped, "watch/src/Main.elm"))
  end

  test "create project writes bundle metadata manifest" do
    slug = "manifest-create-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ManifestCreate",
               "slug" => slug,
               "target_type" => "app"
             })

    manifest_path = Path.join(Projects.project_workspace_path(project), "elm-pebble.project.json")
    assert {:ok, raw} = File.read(manifest_path)
    assert {:ok, decoded} = Jason.decode(raw)
    assert decoded["name"] == "ManifestCreate"
    assert decoded["slug"] == slug
    assert decoded["target_type"] == "app"
    assert decoded["import_path"] == "."
    assert Enum.sort(decoded["source_roots"]) == ["phone", "protocol", "watch"]
    assert decoded["debugger_settings"] == %{}
    assert is_binary(decoded["app_uuid"])
    assert decoded["app_uuid"] == Ide.PebbleToolchain.deterministic_app_uuid(slug)
  end

  test "ensure_app_uuid writes manifest uuid from slug when missing" do
    slug = "uuid-ensure-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "UuidEnsure",
               "slug" => slug,
               "target_type" => "app"
             })

    workspace = Projects.project_workspace_path(project)
    expected = Ide.PebbleToolchain.deterministic_app_uuid(slug)

    assert {:ok, raw} = File.read(Path.join(workspace, "elm-pebble.project.json"))
    assert {:ok, %{"app_uuid" => ^expected}} = Jason.decode(raw)

    {:ok, _} =
      Projects.update_project(project, %{"app_uuid" => nil})

    File.write!(
      Path.join(workspace, "elm-pebble.project.json"),
      Jason.encode!(%{
        "schema_version" => 1,
        "name" => "UuidEnsure",
        "slug" => slug,
        "target_type" => "app",
        "source_roots" => ["watch", "protocol", "phone"],
        "import_path" => "."
      })
    )

    assert reloaded = Projects.get_project!(project.id)
    assert reloaded.app_uuid == nil

    assert {:ok, ensured} = Projects.ensure_app_uuid(reloaded)
    assert ensured.app_uuid == expected

    assert {:ok, raw_after} = File.read(Path.join(workspace, "elm-pebble.project.json"))
    assert {:ok, %{"app_uuid" => ^expected}} = Jason.decode(raw_after)
  end

  test "import project reads bundle metadata and nested import path" do
    source_root =
      Path.join(
        System.tmp_dir!(),
        "ide_import_manifest_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(source_root, "bundle/watch/src"))

    File.write!(
      Path.join(source_root, "bundle/watch/src/Main.elm"),
      "module Main exposing (main)"
    )

    File.write!(
      Path.join(source_root, "elm-pebble.project.json"),
      Jason.encode!(%{
        "schema_version" => 1,
        "name" => "Bundled Import",
        "slug" => "bundled-import",
        "target_type" => "watchface",
        "source_roots" => ["watch", "protocol", "phone"],
        "import_path" => "bundle",
        "debugger_settings" => %{"auto_fire" => %{"watch" => true}}
      })
    )

    on_exit(fn -> File.rm_rf(source_root) end)

    assert {:ok, project} = Projects.import_project(%{}, source_root)
    assert project.name == "Bundled Import"
    assert project.slug == "bundled-import"
    assert project.target_type == "watchface"
    assert project.debugger_settings == %{"auto_fire" => %{"watch" => true}}
    assert {:ok, _} = Projects.read_source_file(project, "watch", "src/Main.elm")
  end

  test "export project creates zip with manifest and sources" do
    slug = "export-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Exportable",
               "slug" => slug,
               "target_type" => "app"
             })

    assert :ok =
             Projects.write_source_file(
               project,
               "watch",
               "src/Main.elm",
               "module Main exposing (main)"
             )

    hidden_build_dir = Path.join(Projects.project_workspace_path(project), "watch/.elmc-build")
    File.mkdir_p!(hidden_build_dir)
    File.write!(Path.join(hidden_build_dir, "generated.c"), "/* generated */")

    assert {:ok, zip_path} = Projects.export_project(project)
    assert File.exists?(zip_path)

    assert {:ok, zip_entries} = :zip.table(String.to_charlist(zip_path))

    file_names =
      zip_entries
      |> Enum.flat_map(fn
        {:zip_file, name, _info, _comment, _offset, _size} ->
          [to_string(name)]

        {:zip_file, name, _info, _comment, _offset, _comp_size, _uncomp_size} ->
          [to_string(name)]

        _other ->
          []
      end)

    assert "elm-pebble.project.json" in file_names
    assert "watch/src/Main.elm" in file_names
    refute "watch/.elmc-build/generated.c" in file_names
  end

  test "import_from_github imports clone path and records github config" do
    clone_path =
      Path.join(System.tmp_dir!(), "ide_github_import_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(clone_path, "watch/src"))
    File.write!(Path.join(clone_path, "watch/src/Main.elm"), "module Main exposing (main)")

    File.write!(
      Path.join(clone_path, "elm-pebble.project.json"),
      Jason.encode!(%{
        "schema_version" => 1,
        "name" => "Github Import",
        "slug" => "github-import",
        "target_type" => "watchface",
        "source_roots" => ["watch", "protocol", "phone"]
      })
    )

    on_exit(fn -> File.rm_rf(clone_path) end)

    assert {:ok, project} =
             Projects.import_from_github(
               %{},
               %{"owner" => "pebbledev", "repo" => "my-watchface", "branch" => "main"},
               nil,
               clone_path: clone_path
             )

    assert project.name == "Github Import"
    assert project.slug == "github-import"

    assert project.github == %{
             "owner" => "pebbledev",
             "repo" => "my-watchface",
             "branch" => "main",
             "visibility" => "public"
           }

    assert {:ok, _} = Projects.read_source_file(project, "watch", "src/Main.elm")
    refute File.exists?(clone_path)
  end

  test "import_from_github infers slug from repo when manifest is absent" do
    clone_path =
      Path.join(
        System.tmp_dir!(),
        "ide_github_import_infer_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(clone_path, "watch/src"))
    File.write!(Path.join(clone_path, "watch/src/Main.elm"), "module Main exposing (main)")
    on_exit(fn -> File.rm_rf(clone_path) end)

    assert {:ok, project} =
             Projects.import_from_github(
               %{},
               %{"repo_url" => "https://github.com/pebbledev/cool-watchface"},
               nil,
               clone_path: clone_path
             )

    assert project.name == "Cool Watchface"
    assert project.slug == "cool-watchface"
    assert project.target_type == "watchface"
    assert project.github["owner"] == "pebbledev"
    assert project.github["repo"] == "cool-watchface"
  end

  test "import_from_github returns error when repo is missing" do
    assert {:error, :missing_github_repo} =
             Projects.import_from_github(%{}, %{"repo_url" => "", "owner" => "", "repo" => ""})
  end

  test "debugger queues companion protocol until phone reload delivers init" do
    slug = "lazy-companion-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Lazy Companion",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-yes"
             })

    assert {:ok, watch_source} = Projects.read_source_file(project, "watch", "src/Main.elm")

    assert {:ok, companion_source} =
             Projects.read_source_file(project, "phone", "src/CompanionApp.elm")

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, after_watch} =
             Debugger.reload(slug, %{
               rel_path: "watch/src/Main.elm",
               source: watch_source,
               reason: "lazy_companion_boot",
               source_root: "watch"
             })

    refute Enum.any?(after_watch.debugger_timeline, fn row ->
             row.type == "init" and row.target == "phone"
           end)

    assert AppMessageQueue.pending?(after_watch, :companion)

    assert {:ok, reloaded} =
             Debugger.reload(slug, %{
               rel_path: "phone/src/CompanionApp.elm",
               source: companion_source,
               reason: "lazy_companion_boot_companion",
               source_root: "phone"
             })

    assert Enum.any?(reloaded.debugger_timeline, fn row ->
             row.type == "init" and row.target == "phone"
           end)

    assert :ok = Debugger.RuntimeBackgroundDrains.await_idle(slug, 120_000)
    assert {:ok, after_drain} = Debugger.snapshot(slug, event_limit: 500)

    assert Enum.any?(after_drain.debugger_timeline, fn row ->
             row.target == "phone" and row.type == "update" and
               String.contains?(to_string(row.message || ""), "FromWatch")
           end) or
             Enum.any?(after_drain.events, fn event ->
               event.type == "debugger.protocol_rx" and
                 String.contains?(inspect(event.payload), "FromWatch")
             end)

    refute AppMessageQueue.pending?(after_drain, :companion)

    companion_shell = get_in(after_drain, [:companion, :shell]) || %{}
    companion_model = get_in(after_drain, [:companion, :model]) || %{}
    companion_runtime = Map.get(companion_model, "runtime_model") || %{}

    assert get_in(companion_shell, ["debugger_contract", "module"]) == "CompanionApp"
    refute Map.has_key?(companion_model, "elm_introspect")
    assert %{"ctor" => "Just", "args" => [settings]} = companion_runtime["settings"]
    assert is_map(settings)
    refute Map.has_key?(settings, "$var")
    assert companion_runtime["errors"] == []
    assert companion_runtime["protocol_message_count"] >= 1
    refute st_has_internal_text_tuple?(after_drain.watch.view_tree)
  end

  test "tangram companion bootstrap reload executes CompanionApp init model" do
    slug = "tangram-companion-bootstrap-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Tangram Companion Bootstrap",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    assert {:ok, companion_source} =
             Projects.read_source_file(project, "phone", "src/CompanionApp.elm")

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, state} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: companion_source,
               reason: "debugger_companion_bootstrap",
               source_root: "phone"
             })

    companion_shell = get_in(state, [:companion, :shell]) || %{}
    companion_model = get_in(state, [:companion, :model]) || %{}
    companion_runtime = Map.get(companion_model, "runtime_model") || %{}

    assert get_in(companion_shell, ["debugger_contract", "module"]) == "CompanionApp"
    refute Map.has_key?(companion_model, "elm_introspect")
    assert companion_runtime["figure"] == 0
    assert companion_runtime["rotationsSinceDownload"] == 0
    assert is_list(companion_runtime["names"]) or is_binary(companion_runtime["names"])
  end

  defp st_has_internal_text_tuple?(value) do
    value
    |> inspect()
    |> String.contains?("{3, {1")
  end

  defp tree_rel_paths(nodes) do
    Enum.flat_map(nodes, fn node ->
      [node.rel_path | tree_rel_paths(Map.get(node, :children, []))]
    end)
  end

  test "pbw_download_filename uses slug and release version label" do
    project = %Project{
      slug: "2048",
      release_defaults: %{"version_label" => "1.2.3"}
    }

    assert Projects.pbw_download_filename(project) == "2048-1.2.3.pbw"
  end

  test "pbw_download_filename sanitizes unsafe characters" do
    project = %Project{
      slug: "my game",
      release_defaults: %{"version_label" => "v 1.0 beta"}
    }

    assert Projects.pbw_download_filename(project) == "my-game-v-1.0-beta.pbw"
  end

  defp minimal_png_bytes do
    <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 2, 0, 0, 0, 3,
      8, 2, 0, 0, 0, 217, 74, 34, 230, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>
  end

  defp write_test_bitmap_png do
    path = Path.join(System.tmp_dir!(), "bitmap_upload_#{System.unique_integer([:positive])}.png")
    bin = System.find_executable("magick") || System.find_executable("convert")

    if is_binary(bin) do
      args =
        if String.ends_with?(Path.basename(bin), "magick"),
          do: [
               "-size",
               "32x32",
               "xc:blue",
               "-fill",
               "yellow",
               "-draw",
               "circle 16,16 16,4",
               "PNG:" <> path
             ],
          else: ["-size", "32x32", "xc:blue", "-fill", "yellow", "-draw", "circle 16,16 16,4", path]

      {_, 0} = System.cmd(bin, args, stderr_to_stdout: true)
      path
    else
      File.write!(path, minimal_png_bytes())
      path
    end
  end
end
