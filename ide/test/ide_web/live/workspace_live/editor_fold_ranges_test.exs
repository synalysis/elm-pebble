defmodule IdeWeb.WorkspaceLive.EditorFoldRangesTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.EditorSupport

  test "top_level_declaration_fold_ranges stop at last non-blank line before next decl" do
    content = """
    update msg model =
        msg

    init flags model =
        flags
    """

    ranges = EditorSupport.top_level_declaration_fold_ranges(content)

    update_fold = Enum.find(ranges, &(&1.start_line == 1))

    assert update_fold.end_line == 2
  end
end
