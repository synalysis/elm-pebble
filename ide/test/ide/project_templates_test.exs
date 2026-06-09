defmodule Ide.ProjectTemplatesTest do
  use Ide.DataCase, async: false

  alias Ide.Emulator.PBW
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

  test "game-2048 template includes aplite after size optimizations" do
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

  test "game-2048 packages for aplite within APP flash limit" do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "game-2048-aplite-#{System.unique_integer([:positive])}"
      )

    assert :ok = ProjectTemplates.apply_template("game-2048", workspace)

    assert {:ok, result} =
             Ide.PebbleToolchain.package("game-2048-aplite",
               workspace_root: workspace,
               target_type: "app",
               project_name: "2048",
               target_platforms: ["aplite"]
             )

    assert {:ok, %{uuid: _uuid}} = PBW.load(result.artifact_path, "aplite")

    elf_path = Path.join(result.app_root, "build/aplite/pebble-app.elf")
    assert File.regular?(elf_path)

    # Aplite APP is 24 KiB total (.text + .data + .bss), not pebble-app.bin alone.
    app_usage = aplite_app_region_bytes(elf_path)

    assert app_usage <= 24_576

    assert app_usage <= 24_576 - 512,
           "expected at least 512 B APP headroom on aplite, got #{24_576 - app_usage}"
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

  defp aplite_app_region_bytes(elf_path) do
    size_bin =
      System.find_executable("arm-none-eabi-size") ||
        sdk_arm_tool("arm-none-eabi-size") ||
        flunk("arm-none-eabi-size not found (install Pebble SDK toolchain)")

    case System.cmd(size_bin, [elf_path]) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.at(1)
        |> String.split(~r/\s+/, trim: true)
        |> then(fn [text, data, bss | _] ->
          String.to_integer(text) + String.to_integer(data) + String.to_integer(bss)
        end)

      {output, _} ->
        flunk("arm-none-eabi-size failed for #{elf_path}: #{output}")
    end
  end

  defp sdk_arm_tool(name) do
    home = System.get_env("HOME")

    if is_binary(home) do
      path =
        Path.join(
          home,
          ".pebble-sdk/SDKs/current/toolchain/arm-none-eabi/bin/#{name}"
        )

      if File.regular?(path), do: path
    end
  end
end
