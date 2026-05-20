defmodule Ide.ScreenshotsTest do
  use ExUnit.Case, async: false

  alias Ide.Projects.Project
  alias Ide.Screenshots

  setup do
    root =
      Path.join(System.tmp_dir!(), "ide_screenshots_test_#{System.unique_integer([:positive])}")

    projects_root = Path.join(root, "projects")
    previous_projects = Application.get_env(:ide, Ide.Projects)
    previous_screenshots = Application.get_env(:ide, Ide.Screenshots)

    Application.put_env(:ide, Ide.Projects, projects_root: projects_root)

    Application.put_env(:ide, Ide.Screenshots,
      storage_root: Path.join(root, "legacy_screenshots"),
      public_prefix: "/screenshots"
    )

    project = %Project{
      id: 1,
      slug: "demo",
      name: "Demo",
      owner_id: 1,
      source_roots: ["src"],
      target_type: "watchface",
      active: true
    }

    on_exit(fn ->
      File.rm_rf(root)

      restore_env(:ide, Ide.Projects, previous_projects)
      restore_env(:ide, Ide.Screenshots, previous_screenshots)
    end)

    {:ok, root: root, projects_root: projects_root, project: project}
  end

  test "stores screenshots under project workspace screenshots/", %{project: project, projects_root: projects_root} do
    png = sample_png(180, 180)

    assert {:ok, stored} = Screenshots.store_png(project, "chalk", png)
    assert stored.mime_type == "image/png"
    assert stored.url == "/projects/demo/screenshots/chalk/#{stored.filename}"

    expected_dir = Path.join([projects_root, "users", "1", "demo", "screenshots", "chalk"])
    assert String.starts_with?(stored.absolute_path, expected_dir)
    assert File.exists?(stored.absolute_path <> ".json")

    assert {:ok, [listed]} = Screenshots.list(project, [])
    assert listed.filename == stored.filename
  end

  test "migrates legacy global screenshots into workspace on first list", %{
    project: project,
    root: root
  } do
    legacy_dir = Path.join(root, "legacy_screenshots/demo/basalt")
    File.mkdir_p!(legacy_dir)
    legacy_path = Path.join(legacy_dir, "legacy.png")
    File.write!(legacy_path, <<137, 80, 78, 71, 13, 10, 26, 10>>)

    assert {:ok, [listed]} = Screenshots.list(project, [])
    assert listed.filename == "legacy.png"
    assert listed.emulator_target == "basalt"
    assert String.contains?(listed.absolute_path, "/screenshots/basalt/legacy.png")
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  defp sample_png(width, height) do
    raw =
      for _y <- 0..(height - 1), into: <<>> do
        <<0>> <> :binary.copy(<<1, 2, 3, 255>>, width)
      end
      |> IO.iodata_to_binary()

    z = :zlib.open()
    :ok = :zlib.deflateInit(z)
    compressed = :zlib.deflate(z, raw, :finish)
    :ok = :zlib.deflateEnd(z)
    :zlib.close(z)
    idat = IO.iodata_to_binary(compressed)

    ihdr = <<width::unsigned-big-32, height::unsigned-big-32, 8, 6, 0, 0, 0>>

    IO.iodata_to_binary([
      <<137, 80, 78, 71, 13, 10, 26, 10>>,
      png_chunk("IHDR", ihdr),
      png_chunk("IDAT", idat),
      png_chunk("IEND", <<>>)
    ])
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32(type <> data)

    <<
      byte_size(data)::unsigned-big-32,
      type::binary,
      data::binary,
      crc::unsigned-big-32
    >>
  end
end
