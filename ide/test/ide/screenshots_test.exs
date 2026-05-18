defmodule Ide.ScreenshotsTest do
  use ExUnit.Case, async: false

  alias Ide.Screenshots

  setup do
    root =
      Path.join(System.tmp_dir!(), "ide_screenshots_test_#{System.unique_integer([:positive])}")

    previous_env = Application.get_env(:ide, Ide.Screenshots)

    Application.put_env(:ide, Ide.Screenshots,
      storage_root: root,
      public_prefix: "/screenshots"
    )

    on_exit(fn ->
      File.rm_rf(root)

      if previous_env == nil do
        Application.delete_env(:ide, Ide.Screenshots)
      else
        Application.put_env(:ide, Ide.Screenshots, previous_env)
      end
    end)

    {:ok, root: root}
  end

  test "stores MIME type metadata alongside browser-captured screenshots", %{root: root} do
    png = <<137, 80, 78, 71, 13, 10, 26, 10, "png-data">>

    assert {:ok, stored} = Screenshots.store_png("demo", "chalk", png)
    assert stored.mime_type == "image/png"

    metadata_path = stored.absolute_path <> ".json"
    assert File.exists?(metadata_path)
    assert {:ok, metadata} = metadata_path |> File.read!() |> Jason.decode()
    assert metadata["mime_type"] == "image/png"
    assert is_binary(metadata["captured_at"])

    assert {:ok, [listed]} = Screenshots.list("demo", [])
    assert listed.filename == stored.filename
    assert listed.emulator_target == "chalk"
    assert listed.mime_type == "image/png"
    assert listed.captured_at == metadata["captured_at"]
    assert listed.absolute_path == Path.join([root, "demo", "chalk", stored.filename])
  end

  test "falls back to file extension for legacy screenshots without metadata", %{root: root} do
    target_dir = Path.join([root, "demo", "basalt"])
    File.mkdir_p!(target_dir)
    legacy_path = Path.join(target_dir, "legacy.webp")
    File.write!(legacy_path, "webp")

    assert {:ok, [listed]} = Screenshots.list("demo", [])
    assert listed.filename == "legacy.webp"
    assert listed.mime_type == "image/webp"
  end
end
