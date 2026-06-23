defmodule Ide.PackageDocs.ExtractorTest do
  use ExUnit.Case, async: true

  alias Ide.PackageDocs.Extractor

  test "builds official docs.json module maps from elm_ex metadata" do
    package_root = package_fixture()

    assert {:ok, [module_doc]} = Extractor.build_package_docs(package_root)

    assert module_doc["name"] == "Sample"
    assert module_doc["comment"] =~ "Sample docs"
    assert module_doc["binops"] == []

    assert [%{"name" => "Thing", "cases" => [["One", []], ["Two", ["Int"]]]}] =
             module_doc["unions"]

    assert [%{"name" => "Alias", "type" => "    { name : String\n    }"}] = module_doc["aliases"]
    assert [%{"name" => "value", "type" => "Int"}] = module_doc["values"]
  end

  test "real Pebble modules have package docs with examples and @docs references" do
    cmd_path =
      Path.expand("../../../../packages/elm-pebble/elm-watch/src/Pebble/Cmd.elm", __DIR__)

    ui_path =
      Path.expand("../../../../packages/elm-pebble/elm-watch/src/Pebble/Ui.elm", __DIR__)

    accel_path =
      Path.expand("../../../../packages/elm-pebble/elm-watch/src/Pebble/Accel.elm", __DIR__)

    speaker_path =
      Path.expand("../../../../packages/elm-pebble/elm-watch/src/Pebble/Speaker.elm", __DIR__)

    storage_companion_path =
      Path.expand(
        "../../../../packages/elm-pebble-companion-core/src/Pebble/Companion/Storage.elm",
        __DIR__
      )

    assert {:ok, cmd_doc} = Extractor.build_module_doc(cmd_path)
    assert cmd_doc["comment"] =~ "timerAfter"
    assert cmd_doc["comment"] =~ "Tick"
    assert Enum.any?(cmd_doc["values"], &(&1["name"] == "timerAfter"))

    assert {:ok, ui_doc} = Extractor.build_module_doc(ui_path)
    assert ui_doc["comment"] =~ "mainWindow"
    assert ui_doc["comment"] =~ "watch-demo-drawing-showcase"
    assert Enum.any?(ui_doc["aliases"], &(&1["name"] == "StaticBitmap"))

    assert {:ok, accel_doc} = Extractor.build_module_doc(accel_path)
    assert accel_doc["comment"] =~ "watch-demo-accel"
    assert accel_doc["comment"] =~ "onData"

    assert {:ok, speaker_doc} = Extractor.build_module_doc(speaker_path)
    assert speaker_doc["comment"] =~ "onFinished"
    assert speaker_doc["comment"] =~ "playNotes"

    assert {:ok, storage_doc} = Extractor.build_module_doc(storage_companion_path)
    assert storage_doc["comment"] =~ "Storage.get"
    assert storage_doc["comment"] =~ "companion-demo-storage"

    unobstructed_path =
      Path.expand(
        "../../../../packages/elm-pebble/elm-watch/src/Pebble/UnobstructedArea.elm",
        __DIR__
      )

    assert {:ok, unobstructed_doc} = Extractor.build_module_doc(unobstructed_path)

    assert [%{"label" => "UnobstructedArea", "url" => url}] =
             unobstructed_doc["native_api_links"]

    assert url == "https://developer.repebble.com/docs/c/User_Interface/UnobstructedArea/"
    assert unobstructed_doc["comment"] =~ "currentBounds"
  end

  defp package_fixture do
    root =
      Path.join([
        System.tmp_dir!(),
        "ide_package_docs_extractor_test_#{System.unique_integer([:positive])}"
      ])

    File.mkdir_p!(Path.join(root, "src"))

    File.write!(
      Path.join(root, "elm.json"),
      Jason.encode!(%{
        "type" => "package",
        "name" => "example/sample",
        "summary" => "Sample package",
        "license" => "MIT",
        "version" => "1.0.0",
        "exposed-modules" => ["Sample"],
        "elm-version" => "0.19.0 <= v < 0.20.0",
        "dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"},
        "test-dependencies" => %{}
      })
    )

    File.write!(Path.join(root, "src/Sample.elm"), """
    module Sample exposing (Alias, Thing(..), value)

    {-| Sample docs.

    # Everything
    @docs Thing, Alias, value

    -}

    {-| A documented custom type.
    -}
    type Thing
        = One
        | Two Int

    {-| A documented alias.
    -}
    type alias Alias =
        { name : String
        }

    {-| A documented value.
    -}
    value : Int
    value =
        1
    """)

    root
  end
end
