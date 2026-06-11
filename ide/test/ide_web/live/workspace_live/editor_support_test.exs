defmodule IdeWeb.WorkspaceLive.EditorSupportTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.EditorSupport

  defp tab(content, opts \\ []) do
    saved_content = Keyword.get(opts, :saved_content, content)

    %{
      id: "watch:src/Main.elm",
      source_root: "watch",
      rel_path: "src/Main.elm",
      content: content,
      saved_content: saved_content,
      dirty: Keyword.get(opts, :dirty, false)
    }
  end

  test "apply_editor_content marks dirty when content differs from saved baseline" do
    baseline = "module Main exposing (main)\n\nmain = 1\n"
    edited = baseline <> "\n"

    tab = tab(baseline)
    updated = EditorSupport.apply_editor_content(tab, edited)

    assert updated.dirty
    assert updated.content == edited
  end

  test "apply_editor_content clears dirty when content matches saved baseline again" do
    baseline = "module Main exposing (main)\n\nmain = 1\n"
    edited = baseline <> "\n"

    tab =
      tab(edited, dirty: true, saved_content: baseline)
      |> EditorSupport.apply_editor_content(baseline)

    refute tab.dirty
    assert tab.content == baseline
  end

  test "mark_editor_content_saved resets baseline after save" do
    baseline = "saved\n"
    tab = tab("edited\n", dirty: true) |> EditorSupport.mark_editor_content_saved(baseline)

    refute tab.dirty
    assert tab.content == baseline
    assert tab.saved_content == baseline
    refute EditorSupport.editor_content_dirty?(tab, baseline)
  end

  test "prepare_content_for_save skips auto-format when source matches saved baseline" do
    source = "module Main exposing (main)\n\nmain = 1\n"
    tab = tab(source)
    project = %{slug: "demo"}

    assert {^source, "Saved Main.elm", nil, %{status: :unchanged, rel_path: "src/Main.elm"}} =
             EditorSupport.prepare_content_for_save(
               project,
               tab,
               true,
               :elm_format,
               nil,
               []
             )
  end
end
