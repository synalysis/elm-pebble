defmodule Elmx.ConformanceScorecardTest do
  use ExUnit.Case

  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer
  alias Elmx.Backend.ElixirCodegen

  @project_dir Path.expand("fixtures/simple_project", __DIR__)
  @tmp Path.expand("../test/tmp/conformance", __DIR__)

  test "writes elmx conformance scorecard from simple_project compile gate" do
    File.mkdir_p!(@tmp)

    {:ok, project} = Bridge.load_project(@project_dir)
    {:ok, ir} = Lowerer.lower_project(project)
    ir_sha = Elmx.IRDigest.sha256(ir)

    assert {:ok, modules} =
             ElixirCodegen.emit_project(ir, %{
               entry_module: "Main",
               mode: :ide_runtime,
               ir_sha256: ir_sha,
               user_module_names: Elmx.user_module_names(project)
             })

    revision = "scorecard-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %Elmx.CompileResult{}} =
             Elmx.compile_in_memory(@project_dir, %{
               revision: revision,
               strip_dead_code: true,
               mode: :ide_runtime
             })

    scorecard = %{
      "elmx_version" => "0.1.0",
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "status" => "simple_project_green",
      "emitted_modules" => length(modules),
      "registered_revision" => revision,
      "module_loaded" => Elmx.module_for_revision(revision) != nil
    }

    json_path = Path.join(@tmp, "scorecard.json")
    md_path = Path.join(@tmp, "scorecard.md")

    File.write!(json_path, Jason.encode!(scorecard, pretty: true))

    File.write!(
      md_path,
      """
      # Elmx conformance scorecard

      - Status: #{scorecard["status"]}
      - Emitted modules: #{scorecard["emitted_modules"]}
      - In-memory module registered: #{scorecard["module_loaded"]}
      """
    )

    assert File.exists?(json_path)
    assert File.exists?(md_path)
  end
end
