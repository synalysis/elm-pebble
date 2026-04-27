defmodule Elmc.ManifestCompatibilityTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  test "manifest includes dependency compatibility rows for blocked families" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)

    output =
      capture_io(fn ->
        assert :ok = Elmc.CLI.main(["manifest", project_dir])
      end)

    manifest = Jason.decode!(output)
    rows = Map.get(manifest, "dependency_compatibility", [])

    assert is_list(rows)

    assert Enum.any?(rows, fn row ->
             row["package"] == "elm/core" and row["status"] == "blocked" and
               row["reason_code"] == "blocked_runtime_family"
           end)

    assert Enum.any?(rows, fn row ->
             row["package"] == "elm/json" and row["status"] == "supported" and
               row["reason_code"] == "allowed"
           end)

    assert "elm/core" in Map.get(manifest, "excluded_packages", [])
    assert "elm/json" in Map.get(manifest, "supported_packages", [])
  end

  test "manifest marks all configured blocked families as blocked" do
    root =
      Path.join(System.tmp_dir!(), "elmc_manifest_compat_#{System.unique_integer([:positive])}")

    src_dir = Path.join(root, "src")
    elm_json = Path.join(root, "elm.json")
    main_elm = Path.join(src_dir, "Main.elm")

    File.mkdir_p!(src_dir)

    File.write!(
      main_elm,
      """
      module Main exposing (main)

      main = 1
      """
    )

    File.write!(
      elm_json,
      Jason.encode!(
        %{
          type: "application",
          "source-directories": ["src"],
          "elm-version": "0.19.1",
          dependencies: %{
            direct: %{
              "elm/core" => "1.0.5",
              "elm/browser" => "1.0.2",
              "elm/bytes" => "1.0.8",
              "elm/file" => "1.0.5",
              "elm/html" => "1.0.0",
              "elm/http" => "2.0.0",
              "elm/json" => "1.1.3"
            },
            indirect: %{}
          },
          "test-dependencies": %{direct: %{}, indirect: %{}}
        },
        pretty: true
      )
    )

    on_exit(fn -> File.rm_rf(root) end)

    output =
      capture_io(fn ->
        assert :ok = Elmc.CLI.main(["manifest", root])
      end)

    manifest = Jason.decode!(output)

    rows =
      manifest
      |> Map.get("dependency_compatibility", [])
      |> Map.new(fn row -> {row["package"], row} end)

    for blocked <- ~w(elm/core elm/browser elm/bytes elm/file elm/html elm/http) do
      assert rows[blocked]["status"] == "blocked"
      assert rows[blocked]["reason_code"] == "blocked_runtime_family"
    end

    assert rows["elm/json"]["status"] == "supported"
    assert rows["elm/json"]["reason_code"] == "allowed"
  end
end
