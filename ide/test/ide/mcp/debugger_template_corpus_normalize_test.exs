defmodule Ide.Mcp.DebuggerTemplateCorpusNormalizeTest do
  use ExUnit.Case, async: true

  alias Ide.Mcp.DebuggerTemplateCorpus

  test "normalize_snapshot canonicalizes legacy and wire timeline messages" do
    legacy = %{
      "timeline_init_messages" => [
        "update:BestLoaded BestLoaded \"\"",
        "update:RandomGenerated RandomGenerated 42424242",
        "update:Unknown Unknown (Ok %{\"degrees\" => 180.0, \"isValid\" => true})",
        "update:GotPosition GotPosition (Ok %{\"accuracy\" => 25.0, \"latitude\" => 48.137154, \"longitude\" => 11.576124})"
      ]
    }

    wire = %{
      "timeline_init_messages" => [
        "update:BestLoaded \"\"",
        "update:RandomGenerated <seed>",
        "update:Unknown (Ok { degrees = 180, isValid = True })",
        "update:GotPosition (Ok { accuracy = 25, latitude = 48.137154, longitude = 11.576124 })"
      ]
    }

    assert DebuggerTemplateCorpus.normalize_snapshot(legacy) ==
             DebuggerTemplateCorpus.normalize_snapshot(wire)
  end
end
