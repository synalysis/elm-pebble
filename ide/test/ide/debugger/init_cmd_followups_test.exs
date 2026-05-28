defmodule Ide.Debugger.InitCmdFollowupsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.InitCmdFollowups
  alias Ide.Debugger.PendingHttpFollowups
  alias Ide.Debugger.Surface

  @companion_source File.read!(
                       Path.join([
                         "priv",
                         "project_templates",
                         "watchface_tangram_time",
                         "phone",
                         "src",
                         "CompanionApp.elm"
                       ])
                     )

  test "runtime_followup_rows derives Http.get catalog follow-up from init_cmd_calls" do
    assert {:ok, %{"elm_introspect" => ei}} =
             Ide.Debugger.ElmIntrospect.analyze_source(@companion_source, "CompanionApp.elm")

    [followup] = InitCmdFollowups.runtime_followup_rows(ei)

    assert followup["message"] == "CatalogReceived"
    assert followup["package"] == "elm/http"
    assert followup["command"]["kind"] == "http"
    assert followup["command"]["method"] == "GET"

    assert followup["command"]["url"] ==
             "https://raw.githubusercontent.com/lil-lab/kilogram/main/dataset/dense10.json"
  end

  test "merge_followups keeps executor rows and adds init http when missing" do
    assert {:ok, %{"elm_introspect" => ei}} =
             Ide.Debugger.ElmIntrospect.analyze_source(@companion_source, "CompanionApp.elm")

    merged =
      InitCmdFollowups.merge_followups(
        [%{"message" => "Other", "package" => "elm/http", "command" => %{"url" => "https://example.test"}}],
        ei
      )

    assert length(merged) == 2
    assert Enum.any?(merged, &(&1["message"] == "CatalogReceived"))
    assert Enum.any?(merged, &(&1["message"] == "Other"))
  end

  test "async http pending survives companion surface round-trip" do
    state = %{companion: %{model: %{}, shell: %{}}}

    state =
      PendingHttpFollowups.enqueue(
        state,
        :companion,
        "phone",
        "elm/http",
        %{"kind" => "http", "url" => "https://example.test"},
        "CatalogReceived"
      )

    state =
      state
      |> Surface.from_state(:companion)
      |> then(&Surface.put_in_state(state, :companion, &1))

    assert [%{"followup_message" => "CatalogReceived"}] = PendingHttpFollowups.pending(state)
  end

  test "merge_followups dedupes duplicate http urls" do
    assert {:ok, %{"elm_introspect" => ei}} =
             Ide.Debugger.ElmIntrospect.analyze_source(@companion_source, "CompanionApp.elm")

    [catalog] = InitCmdFollowups.runtime_followup_rows(ei)

    merged =
      InitCmdFollowups.merge_followups([catalog], ei)

    assert length(merged) == 1
  end
end
