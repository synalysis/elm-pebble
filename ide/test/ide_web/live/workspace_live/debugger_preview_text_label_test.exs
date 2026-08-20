defmodule IdeWeb.WorkspaceLive.DebuggerPreviewTextLabelTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.DebuggerPreview
  alias IdeWeb.WorkspaceLive.DebuggerPreview.SvgOpNormalize

  test "preview keeps app textLabel strings and does not invent Label" do
    assert DebuggerPreview.text_label_from_node(%{
             "type" => "textLabel",
             "children" => [
               %{"type" => "font"},
               %{"type" => "point"},
               %{"type" => "string", "value" => "Make it count"}
             ]
           }) == "Make it count"

    assert DebuggerPreview.text_label_from_node(%{"type" => "textLabel", "children" => []}) == ""
    assert DebuggerPreview.text_label_from_node(%{}) == ""
  end

  test "preview resolves only the Pebble.Ui.Label constructor" do
    waiting = "Waiting for companion app"

    assert DebuggerPreview.text_label_from_node(%{
             "type" => "textLabel",
             "children" => [
               %{"type" => "font"},
               %{"type" => "point"},
               %{
                 "type" => "WaitingForCompanion",
                 "qualified_target" => "Pebble.Ui.WaitingForCompanion"
               }
             ]
           }) == waiting

    assert DebuggerPreview.text_label_from_node(%{
             "type" => "textLabel",
             "children" => [
               %{"type" => "font"},
               %{"type" => "point"},
               %{
                 "type" => "WaitingForCompanion",
                 "qualified_target" => "Main.WaitingForCompanion"
               }
             ]
           }) == ""

    assert DebuggerPreview.text_label_from_node(%{
             "type" => "textLabel",
             "children" => [
               %{"type" => "font"},
               %{"type" => "point"},
               %{"type" => "WaitingForCompanion"}
             ]
           }) == waiting
  end

  test "svg text_label uses command text, never tag 0" do
    assert %{kind: :text_label, text: "Daily quote"} =
             SvgOpNormalize.normalize(%{
               "kind" => "text_label",
               "x" => 4,
               "y" => 28,
               "text" => "Daily quote",
               "label_tag" => 0
             })

    assert %{kind: :unresolved, node_type: "text_label"} =
             SvgOpNormalize.normalize(%{
               "kind" => "text_label",
               "x" => 4,
               "y" => 28,
               "text" => "",
               "label_tag" => 0,
               "p3" => 0
             })

    assert %{kind: :text_label, text: "Waiting for companion app"} =
             SvgOpNormalize.normalize(%{
               "kind" => "text_label",
               "x" => 0,
               "y" => 28,
               "text" => "Pebble.Ui.WaitingForCompanion"
             })
  end
end
