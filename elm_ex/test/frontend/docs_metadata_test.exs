defmodule ElmEx.Frontend.DocsMetadataTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.DocsMetadata

  test "extracts module docs, @docs order, comments, aliases, unions, and values" do
    path = fixture_path("Sample.elm")

    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    module Sample exposing
        ( Alias
        , Thing(..)
        , value
        )

    {-| Sample module docs.

    # Values
    @docs value, Alias, Thing

    -}

    {-| A documented value.
    -}
    value : Int
    value =
        1

    {-| A documented alias.
    -}
    type alias Alias =
        { name : String
        }

    {-| A documented custom type.
    -}
    type Thing
        = One
        | Two Int
    """)

    assert {:ok, metadata} = DocsMetadata.parse_file(path)

    assert metadata.name == "Sample"
    assert metadata.docs == ["value", "Alias", "Thing"]
    assert metadata.module_exposing == ["Alias", "Thing(..)", "value"]
    assert metadata.declarations["value"].comment == "A documented value."
    assert metadata.declarations["Alias"].type == "{ name : String\n}"
    assert metadata.declarations["Thing"].cases == [["One", []], ["Two", ["Int"]]]
  end

  defp fixture_path(file) do
    Path.join([
      System.tmp_dir!(),
      "elm_ex_docs_metadata_test_#{System.unique_integer([:positive])}",
      file
    ])
  end
end
