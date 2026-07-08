defmodule IdeWeb.WorkspaceLive.DebuggerPage.BytecodeArtifactsTest do
  use ExUnit.Case, async: true

  alias IdeWeb.WorkspaceLive.DebuggerPage.BytecodeArtifacts

  test "summary reads elmc_bytecode_manifest from watch runtime model" do
    runtime = %{
      model: %{
        "elmc_bytecode_manifest" => %{
          "available" => true,
          "function_count" => 40,
          "skipped_count" => 5,
          "plan_toolchain" => %{"mode" => "primary", "strict" => true},
          "plan_coverage" => %{
            "main" => %{"lowered" => 11, "total" => 11, "failed_count" => 0, "ratio" => 1.0},
            "reachable" => %{"lowered" => 40, "total" => 40, "failed_count" => 0, "ratio" => 1.0}
          },
          "functions" => [
            %{"module" => "Main", "name" => "init"},
            %{"module" => "Pebble.Ui", "name" => "textInt"}
          ]
        }
      }
    }

    manifest = BytecodeArtifacts.summary(runtime)
    assert BytecodeArtifacts.available?(manifest)
    assert BytecodeArtifacts.headline(manifest) =~ "plan primary strict"
    assert BytecodeArtifacts.headline(manifest) =~ "40 bytecode functions"
    assert BytecodeArtifacts.headline(manifest) =~ "Main 11/11 lowered"
    assert BytecodeArtifacts.headline(manifest) =~ "reachable 40/40 lowered"
    assert length(BytecodeArtifacts.main_functions(manifest)) == 1
    assert BytecodeArtifacts.format_result({:render_cmd, 1, [42]}) =~ "render_cmd"
    assert BytecodeArtifacts.smoke_label(%{target: {"Main", "init"}, status: :ok, text: "0"}) =~ "Main.init"
  end
end
