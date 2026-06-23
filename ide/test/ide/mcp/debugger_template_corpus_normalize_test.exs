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

  test "normalize_snapshot dedupes duplicate init timeline entries" do
    with_dupes = %{
      "timeline_init_messages" => [
        "init:init",
        "update:CurrentDateTime { day = 27, hour = 8, minute = 53 }",
        "update:CurrentDateTime { day = 27, hour = 8, minute = 53 }",
        "update:FromPhone (ProvideCondition Fog)",
        "update:GotWeather (Ok (Current { condition = Fog, temperatureC = 18 }))",
        "update:GotWeather (Ok (Current { condition = Fog, temperatureC = 18 }))"
      ]
    }

    without_dupes = %{
      "timeline_init_messages" => [
        "init:init",
        "update:CurrentDateTime { day = 27, hour = 8, minute = 53 }",
        "update:FromPhone (ProvideCondition Fog)",
        "update:GotWeather (Ok (Current { condition = Fog, temperatureC = 18 }))"
      ]
    }

    assert DebuggerTemplateCorpus.normalize_snapshot(with_dupes) ==
             DebuggerTemplateCorpus.normalize_snapshot(without_dupes)
  end
end
