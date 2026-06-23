defmodule Ide.ProjectTemplatesTest do
  use Ide.DataCase, async: false

  alias Ide.ProjectTemplates
  alias Ide.Projects

  setup do
    root =
      Path.join(System.tmp_dir!(), "ide_templates_test_#{System.unique_integer([:positive])}")

    Application.put_env(:ide, Ide.Projects, projects_root: root)
    on_exit(fn -> File.rm_rf(root) end)
    :ok
  end

  test "templates without metadata enable all supported platforms" do
    platforms = ProjectTemplates.target_platforms_for_template("watchface-digital")

    assert "aplite" in platforms
    assert "basalt" in platforms
    assert "gabbro" in platforms
  end

  test "picker_categories groups templates for the create-project modal" do
    categories = ProjectTemplates.picker_categories()

    assert Enum.map(categories, & &1.id) == [
             "starter",
             "watchface",
             "companion",
             "watch_demo",
             "game"
           ]

    starter = Enum.find(categories, &(&1.id == "starter"))
    assert Enum.any?(starter.templates, &(&1.key == "app-minimal"))

    watchface = Enum.find(categories, &(&1.id == "watchface"))
    minimal = Enum.find(watchface.templates, &(&1.key == "watchface-minimal"))
    digital = Enum.find(watchface.templates, &(&1.key == "watchface-digital"))

    assert minimal.title == "Minimal"
    assert minimal.description == "watch-only"
    assert minimal.screenshot_url == "/images/template-previews/watchface-minimal.png"

    assert digital.title == "Digital"
    assert digital.description == "watch-only"
    assert digital.screenshot_url == "/images/template-previews/watchface-digital.png"
  end

  test "picker_title returns the short template title for a key" do
    assert ProjectTemplates.picker_title("starter") == "Starter"
    assert ProjectTemplates.picker_title("watchface-digital") == "Digital"
    assert ProjectTemplates.picker_title("game-2048") == "2048"
  end

  test "every watch demo template key has a static preview screenshot" do
    for key <- ProjectTemplates.template_keys(), String.starts_with?(key, "watch-demo-") do
      assert Ide.ProjectTemplatePreviews.screenshot_available?(key),
             "missing preview screenshot for #{key}"
    end
  end

  test "companion_for_template reflects whether a template seeds phone companion" do
    assert ProjectTemplates.companion_for_template("starter")
    assert ProjectTemplates.companion_for_template("watchface-yes")
    assert ProjectTemplates.companion_for_template("companion-demo-storage")
    refute ProjectTemplates.companion_for_template("watchface-digital")
    refute ProjectTemplates.companion_for_template("game-2048")
    refute ProjectTemplates.companion_for_template("watch-demo-health")
  end

  test "filter_picker_categories filters by project type and companion app" do
    categories = ProjectTemplates.picker_categories()

    watch_only =
      ProjectTemplates.filter_picker_categories(categories, "all", "without")

    assert Enum.flat_map(watch_only, & &1.templates)
           |> Enum.map(& &1.key)
           |> Enum.member?("watchface-digital")

    refute Enum.flat_map(watch_only, & &1.templates)
           |> Enum.map(& &1.key)
           |> Enum.member?("starter")

    watchfaces =
      ProjectTemplates.filter_picker_categories(categories, "watchface", "all")

    assert Enum.all?(
             Enum.flat_map(watchfaces, & &1.templates),
             &(&1.target_type == "watchface")
           )

    refute Enum.flat_map(watchfaces, & &1.templates)
           |> Enum.map(& &1.key)
           |> Enum.member?("game-2048")
  end

  test "minimal templates seed bare watch-only Elm apps" do
    for {template, platform_entry} <- [
          {"watchface-minimal", "Platform.watchface"},
          {"app-minimal", "Platform.application"}
        ] do
      slug = "minimal-template-#{template}-#{System.unique_integer([:positive])}"

      assert {:ok, project} =
               Projects.create_project(%{
                 "name" => "MinimalTemplate",
                 "slug" => slug,
                 "template" => template
               })

      base = Projects.project_workspace_path(project)
      assert {:ok, watch_main} = Projects.read_source_file(project, "watch", "src/Main.elm")
      assert String.contains?(watch_main, platform_entry)
      assert String.contains?(watch_main, "Ui.clear Color.white")
      refute File.exists?(Path.join(base, "protocol/elm.json"))
      refute File.exists?(Path.join(base, "phone/elm.json"))
    end
  end

  test "watchface package writes ELMC_WATCHFACE_MODE build flags" do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "smoke-watchface-flags-#{System.unique_integer([:positive])}"
      )

    assert :ok = ProjectTemplates.apply_template("watchface-smoke-screen", workspace)

    assert {:ok, _} =
             Ide.PebbleToolchain.package("smoke-flags",
               workspace_root: workspace,
               target_type: "watchface",
               project_name: "Smoke",
               target_platforms: ["diorite"]
             )

    flags_path = Path.join(workspace, ".pebble-sdk/app/src/c/elmc_emulator_build_flags.h")
    assert File.read!(flags_path) =~ "ELMC_WATCHFACE_MODE"

    package_json = Jason.decode!(File.read!(Path.join(workspace, ".pebble-sdk/app/package.json")))
    assert get_in(package_json, ["pebble", "watchapp", "watchface"]) == true
  end

  test "watch-demo-speaker seeds bundled PCM sample and generated Resources module" do
    slug = "speaker-template-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "SpeakerTemplate",
               "slug" => slug,
               "template" => "watch-demo-speaker"
             })

    base = Projects.project_workspace_path(project)
    pcm_path = Path.join(base, "watch/resources/speaker_samples/chime.pcm")
    assert File.regular?(pcm_path)
    assert File.stat!(pcm_path).size == 4800

    manifest =
      base
      |> Path.join("watch/resources/speaker_samples.json")
      |> File.read!()
      |> Jason.decode!()

    assert [%{"ctor" => "SampleChime", "filename" => "chime.pcm"}] = manifest["entries"]

    resources_elm = File.read!(Path.join(base, "watch/src/Pebble/Speaker/Resources.elm"))
    assert resources_elm =~ "SampleChime"
    assert resources_elm =~ "allSamples =\n    [ SampleChime ]"

    assert {:ok, main_elm} = Projects.read_source_file(project, "watch", "src/Main.elm")
    assert main_elm =~ "Speaker.playTracks"
  end

  test "watchface-smoke-screen seeds checkerboard Main.elm" do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "smoke-screen-template-#{System.unique_integer([:positive])}"
      )

    assert :ok = ProjectTemplates.apply_template("watchface-smoke-screen", workspace)

    main_path = Path.join(workspace, "watch/src/Main.elm")
    assert File.exists?(main_path)
    assert File.read!(main_path) =~ "checkerboard"
    assert File.read!(main_path) =~ "Ui.fillRect"
    refute File.read!(main_path) =~ "getCurrentTimeString"
  end

  test "watchface-tangram-time template excludes aplite" do
    platforms = ProjectTemplates.target_platforms_for_template("watchface-tangram-time")

    refute "aplite" in platforms
    assert platforms == ["basalt", "chalk", "diorite", "emery", "flint", "gabbro"]
  end

  test "watchface-poke-battle template excludes aplite" do
    platforms = ProjectTemplates.target_platforms_for_template("watchface-poke-battle")

    refute "aplite" in platforms
    assert platforms == ["basalt", "chalk", "diorite", "emery", "flint", "gabbro"]
  end

  test "game-2048 template includes aplite after startup timer removal" do
    platforms = ProjectTemplates.target_platforms_for_template("game-2048")

    assert platforms == [
             "aplite",
             "basalt",
             "chalk",
             "diorite",
             "emery",
             "flint",
             "gabbro"
           ]
  end

  test "watch demo templates with metadata restrict target platforms" do
    compass = ProjectTemplates.target_platforms_for_template("watch-demo-compass")
    dictation = ProjectTemplates.target_platforms_for_template("watch-demo-dictation")
    health = ProjectTemplates.target_platforms_for_template("watch-demo-health")

    assert compass == ["aplite"]
    assert dictation == ["diorite", "emery", "flint"]
    assert health == ["basalt", "chalk", "diorite", "emery", "flint", "gabbro"]
  end

  test "create_project applies template target platform defaults" do
    slug = "tangram-platforms-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Tangram Platforms",
               "slug" => slug,
               "template" => "watchface-tangram-time"
             })

    assert project.release_defaults["target_platforms"] == [
             "basalt",
             "chalk",
             "diorite",
             "emery",
             "flint",
             "gabbro"
           ]
  end

  test "explicit release_defaults override template defaults" do
    slug = "tangram-override-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Tangram Override",
               "slug" => slug,
               "template" => "watchface-tangram-time",
               "release_defaults" => %{"target_platforms" => ["basalt"]}
             })

    assert project.release_defaults["target_platforms"] == ["basalt"]
  end
end
