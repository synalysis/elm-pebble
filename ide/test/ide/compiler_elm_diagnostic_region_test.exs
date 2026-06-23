defmodule Ide.CompilerElmDiagnosticRegionTest do
  use ExUnit.Case, async: true

  alias Ide.Compiler.Diagnostics

  test "elm diagnostics preserve exclusive end region for editor highlights" do
    workspace = tmp_protocol_workspace!()

    assert {:ok, %{status: :error, diagnostics: [diag | _]}} =
             Ide.Compiler.check_source_root("elm-region-#{System.unique_integer([:positive])}",
               workspace_root: workspace,
               source_root: "protocol"
             )

    assert diag.line == 4
    assert diag.column == 19
    assert diag.end_line == 4
    assert diag.end_column == 23
    assert String.contains?(diag.message, "NAMING ERROR")

    normalized = Diagnostics.normalize_list([diag])
    assert hd(normalized).end_line == 4
    assert hd(normalized).end_column == 23
  end

  defp tmp_protocol_workspace! do
    workspace =
      Path.join(
        System.tmp_dir!(),
        "compiler_elm_region_#{System.unique_integer([:positive])}"
      )

    protocol_root = Path.join(workspace, "protocol")
    File.mkdir_p!(Path.join(protocol_root, "src/Companion"))

    File.write!(
      Path.join(protocol_root, "elm.json"),
      Jason.encode!(%{
        "type" => "application",
        "source-directories" => ["src"],
        "elm-version" => "0.19.1",
        "dependencies" => %{
          "direct" => %{"elm/core" => "1.0.5", "elm/json" => "1.1.3"},
          "indirect" => %{}
        },
        "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
      })
    )

    File.write!(
      Path.join(protocol_root, "src/Companion/Types.elm"),
      """
      module Companion.Types exposing (PhoneToWatch(..))

      type PhoneToWatch
          = PushLabels (Dict String Int)
      """
    )

    on_exit(fn -> File.rm_rf(workspace) end)
    workspace
  end
end
