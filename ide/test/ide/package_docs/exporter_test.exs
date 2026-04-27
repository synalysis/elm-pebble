defmodule Ide.PackageDocs.ExporterTest do
  use ExUnit.Case, async: true

  alias Ide.PackageDocs.Exporter

  test "exports docs.json and elm.json under package viewer compatible paths" do
    package_root = package_fixture()
    output_root = output_fixture()

    assert {:ok, result} =
             Exporter.export(
               output_root: output_root,
               packages: [%{name: "example/sample", root: package_root}]
             )

    assert [%{name: "example/sample", version: "1.0.0", modules: ["Sample"]}] = result.packages

    docs_path = Path.join(output_root, "packages/example/sample/1.0.0/docs.json")
    elm_json_path = Path.join(output_root, "packages/example/sample/1.0.0/elm.json")

    assert File.exists?(docs_path)
    assert File.exists?(elm_json_path)

    assert {:ok, [%{"name" => "Sample"}]} = docs_path |> File.read!() |> Jason.decode()
    assert {:ok, %{"name" => "example/sample"}} = elm_json_path |> File.read!() |> Jason.decode()
  end

  defp package_fixture do
    root =
      Path.join([
        System.tmp_dir!(),
        "ide_package_docs_exporter_package_#{System.unique_integer([:positive])}"
      ])

    File.mkdir_p!(Path.join(root, "src"))

    File.write!(Path.join(root, "elm.json"), """
    {
      "type": "package",
      "name": "example/sample",
      "summary": "Sample package",
      "license": "MIT",
      "version": "1.0.0",
      "exposed-modules": ["Sample"],
      "elm-version": "0.19.0 <= v < 0.20.0",
      "dependencies": {
        "elm/core": "1.0.0 <= v < 2.0.0"
      },
      "test-dependencies": {}
    }
    """)

    File.write!(Path.join(root, "src/Sample.elm"), """
    module Sample exposing (value)

    {-| Sample docs.

    # Values
    @docs value

    -}

    {-| A documented value.
    -}
    value : Int
    value =
        1
    """)

    root
  end

  defp output_fixture do
    Path.join([
      System.tmp_dir!(),
      "ide_package_docs_exporter_output_#{System.unique_integer([:positive])}"
    ])
  end
end
