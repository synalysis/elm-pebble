defmodule Ide.Packages.ModuleDocTest do
  use ExUnit.Case, async: true

  alias Ide.Packages.ModuleDoc

  test "indents every line of multiline stripped record alias types" do
    markdown =
      ModuleDoc.json_to_markdown(%{
        "name" => "Demo",
        "comment" => "",
        "unions" => [],
        "aliases" => [
          %{
            "name" => "Config",
            "args" => [],
            "comment" => "",
            "type" => "{ samplesPerUpdate : Int\n, samplingRate : SamplingRate\n}"
          }
        ],
        "values" => [],
        "binops" => []
      })

    assert markdown =~ """
           ```elm
           type alias Config =
               { samplesPerUpdate : Int
               , samplingRate : SamplingRate
               }
           ```
           """

    refute markdown =~ ~r/\n, samplingRate/
  end

  test "keeps pre-indented elm_ex record alias types" do
    markdown =
      ModuleDoc.json_to_markdown(%{
        "name" => "Demo",
        "comment" => "",
        "unions" => [],
        "aliases" => [
          %{
            "name" => "Sample",
            "args" => [],
            "comment" => "",
            "type" => "    { x : Int\n    , y : Int\n    }"
          }
        ],
        "values" => [],
        "binops" => []
      })

    assert markdown =~ """
           ```elm
           type alias Sample =
               { x : Int
               , y : Int
               }
           ```
           """

    refute markdown =~ "        { x : Int"
  end
end
