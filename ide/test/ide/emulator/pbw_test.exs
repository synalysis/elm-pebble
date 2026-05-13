defmodule Ide.Emulator.PbwTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.PBW

  @manifest %{
    "application" => %{"name" => "pebble-app.bin", "size" => 4},
    "resources" => %{"name" => "app_resources.pbpack", "size" => 2}
  }

  test "load selects platform variant and reads binary blobs" do
    appinfo = %{
      "uuid" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "targetPlatforms" => ["basalt"],
      "displayName" => "X",
      "resources" => %{"media" => [%{"name" => "IMAGE", "file" => "image.png"}]}
    }

    dir = Path.join(System.tmp_dir!(), "elm-test-pbw-#{System.unique_integer([:positive])}")
    pbw_path = Path.join(dir, "app.pbw")
    File.mkdir_p!(dir)

    json_a = Jason.encode!(appinfo)
    json_m = Jason.encode!(@manifest)

    assert {:ok, path} =
             :zip.create(
               String.to_charlist(pbw_path),
               [
                 {~c"appinfo.json", json_a},
                 {~c"basalt/manifest.json", json_m},
                 {~c"basalt/pebble-app.bin", <<1, 2, 3, 4>>},
                 {~c"basalt/app_resources.pbpack", <<9, 8>>}
               ],
               []
             )

    assert Path.expand(List.to_string(path)) == Path.expand(pbw_path)

    assert {:ok, pbw} = PBW.load(pbw_path, "basalt")
    assert pbw.variant == "basalt"
    assert pbw.uuid == appinfo["uuid"]
    kinds = Enum.map(pbw.parts, & &1.kind)
    assert kinds == [:binary, :resources]

    File.rm_rf!(dir)
  end

  test "load skips generated resource pack when app declares no media" do
    appinfo = %{
      "uuid" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "targetPlatforms" => ["basalt"],
      "displayName" => "X",
      "resources" => %{"media" => []}
    }

    dir =
      Path.join(
        System.tmp_dir!(),
        "elm-test-pbw-empty-resources-#{System.unique_integer([:positive])}"
      )

    pbw_path = Path.join(dir, "app.pbw")
    File.mkdir_p!(dir)

    assert {:ok, _path} =
             :zip.create(
               String.to_charlist(pbw_path),
               [
                 {~c"appinfo.json", Jason.encode!(appinfo)},
                 {~c"basalt/manifest.json", Jason.encode!(@manifest)},
                 {~c"basalt/pebble-app.bin", <<1, 2, 3, 4>>},
                 {~c"basalt/app_resources.pbpack", <<9, 8>>}
               ],
               []
             )

    assert {:ok, pbw} = PBW.load(pbw_path, "basalt")
    assert Enum.map(pbw.parts, & &1.kind) == [:binary]

    File.rm_rf!(dir)
  end

  test "prune_empty_media_resources leaves placeholder resource pack in artifact" do
    appinfo = %{
      "uuid" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "targetPlatforms" => ["basalt"],
      "displayName" => "X",
      "resources" => %{"media" => []}
    }

    dir =
      Path.join(
        System.tmp_dir!(),
        "elm-test-pbw-prune-empty-resources-#{System.unique_integer([:positive])}"
      )

    pbw_path = Path.join(dir, "app.pbw")
    File.mkdir_p!(dir)

    assert {:ok, _path} =
             :zip.create(
               String.to_charlist(pbw_path),
               [
                 {~c"appinfo.json", Jason.encode!(appinfo)},
                 {~c"basalt/manifest.json", Jason.encode!(@manifest)},
                 {~c"basalt/pebble-app.bin", <<1, 2, 3, 4>>},
                 {~c"basalt/app_resources.pbpack", <<9, 8>>}
               ],
               []
             )

    assert {:ok, ^pbw_path} = PBW.prune_empty_media_resources(pbw_path)
    assert {:ok, entries} = :zip.extract(String.to_charlist(pbw_path), [:memory])

    names = Enum.map(entries, fn {name, _data} -> List.to_string(name) end)
    assert "basalt/app_resources.pbpack" in names

    manifest =
      entries
      |> Enum.find_value(fn
        {~c"basalt/manifest.json", data} -> Jason.decode!(data)
        _ -> nil
      end)

    assert %{"name" => "app_resources.pbpack"} = manifest["resources"]

    File.rm_rf!(dir)
  end

  test "prune_empty_media_resources keeps declared media resource pack" do
    appinfo = %{
      "uuid" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "targetPlatforms" => ["basalt"],
      "displayName" => "X",
      "resources" => %{"media" => [%{"name" => "IMAGE", "file" => "image.png"}]}
    }

    dir =
      Path.join(
        System.tmp_dir!(),
        "elm-test-pbw-keep-media-resources-#{System.unique_integer([:positive])}"
      )

    pbw_path = Path.join(dir, "app.pbw")
    File.mkdir_p!(dir)

    assert {:ok, _path} =
             :zip.create(
               String.to_charlist(pbw_path),
               [
                 {~c"appinfo.json", Jason.encode!(appinfo)},
                 {~c"basalt/manifest.json", Jason.encode!(@manifest)},
                 {~c"basalt/pebble-app.bin", <<1, 2, 3, 4>>},
                 {~c"basalt/app_resources.pbpack", <<9, 8>>}
               ],
               []
             )

    assert {:ok, ^pbw_path} = PBW.prune_empty_media_resources(pbw_path)
    assert {:ok, entries} = :zip.extract(String.to_charlist(pbw_path), [:memory])

    names = Enum.map(entries, fn {name, _data} -> List.to_string(name) end)
    assert "basalt/app_resources.pbpack" in names

    File.rm_rf!(dir)
  end

  test "prune_development_artifacts removes JavaScript source maps from artifact" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "elm-test-pbw-prune-development-artifacts-#{System.unique_integer([:positive])}"
      )

    pbw_path = Path.join(dir, "app.pbw")
    File.mkdir_p!(dir)

    js = """
    console.log("ok");
    //# sourceMappingURL=pebble-js-app.js.map
    """

    assert {:ok, _path} =
             :zip.create(
               String.to_charlist(pbw_path),
               [
                 {~c"appinfo.json",
                  Jason.encode!(%{"uuid" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"})},
                 {~c"pebble-js-app.js", js},
                 {~c"pebble-js-app.js.map", "{}"},
                 {~c"basalt/manifest.json", Jason.encode!(@manifest)},
                 {~c"basalt/pebble-app.bin", <<1, 2, 3, 4>>}
               ],
               []
             )

    assert {:ok, ^pbw_path} = PBW.prune_development_artifacts(pbw_path)
    assert {:ok, entries} = :zip.extract(String.to_charlist(pbw_path), [:memory])

    names = Enum.map(entries, fn {name, _data} -> List.to_string(name) end)
    refute "pebble-js-app.js.map" in names

    js_entry =
      Enum.find_value(entries, fn
        {~c"pebble-js-app.js", data} -> data
        _ -> nil
      end)

    assert js_entry =~ ~S|console.log("ok");|
    refute js_entry =~ "sourceMappingURL"

    File.rm_rf!(dir)
  end

  test "load rejects pbw when appinfo uuid differs from binary header uuid" do
    appinfo_uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    binary_uuid = "3278ae24-9885-427f-90e7-791ac2450e78"

    appinfo = %{
      "uuid" => appinfo_uuid,
      "targetPlatforms" => ["basalt"],
      "displayName" => "X"
    }

    dir = Path.join(System.tmp_dir!(), "elm-test-pbw-#{System.unique_integer([:positive])}")
    pbw_path = Path.join(dir, "app.pbw")
    File.mkdir_p!(dir)

    json_a = Jason.encode!(appinfo)
    json_m = Jason.encode!(@manifest)

    assert {:ok, _path} =
             :zip.create(
               String.to_charlist(pbw_path),
               [
                 {~c"appinfo.json", json_a},
                 {~c"basalt/manifest.json", json_m},
                 {~c"basalt/pebble-app.bin", app_binary(binary_uuid)},
                 {~c"basalt/app_resources.pbpack", <<9, 8>>}
               ],
               []
             )

    assert {:error, {:pbw_uuid_mismatch, ^appinfo_uuid, ^binary_uuid}} =
             PBW.load(pbw_path, "basalt")

    File.rm_rf!(dir)
  end

  defp app_binary(uuid) do
    uuid_bytes = uuid |> String.replace("-", "") |> Base.decode16!(case: :mixed)
    app_name = fixed_string("PBW Test", 32)
    company_name = fixed_string("elm-pebble-ide", 32)

    <<0::64, 1, 0, 5, 86, 1, 0, 0::little-16, 0::little-32, 0::little-32, app_name::binary,
      company_name::binary, 0::little-32, 0::little-32, 137::little-32, 0::little-32,
      uuid_bytes::binary, 0::48>>
  end

  defp fixed_string(value, size) do
    :binary.part(value <> :binary.copy(<<0>>, size), 0, size)
  end
end
