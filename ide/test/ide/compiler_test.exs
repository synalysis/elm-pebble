defmodule Ide.CompilerTest do
  use ExUnit.Case, async: true

  alias ElmExecutor.Runtime.SemanticExecutor
  alias Ide.Compiler
  alias Ide.ProjectTemplates

  test "normalizes valid manifest payload shape" do
    payload = %{
      "supported_packages" => ["elm/core"],
      "excluded_packages" => ["elm/html"],
      "modules_detected" => ["Main"]
    }

    {normalized, diagnostics} = Compiler.normalize_manifest_payload(payload)

    assert normalized.schema_version == 1
    assert normalized.supported_packages == ["elm/core"]
    assert normalized.excluded_packages == ["elm/html"]
    assert normalized.modules_detected == ["Main"]
    assert diagnostics == []
  end

  test "normalizes missing/invalid manifest fields with warnings" do
    payload = %{
      "supported_packages" => ["elm/core", 1],
      "excluded_packages" => "elm/html"
    }

    {normalized, diagnostics} = Compiler.normalize_manifest_payload(payload)

    assert normalized.supported_packages == ["elm/core"]
    assert normalized.excluded_packages == []
    assert normalized.modules_detected == []
    assert length(diagnostics) >= 2
    assert Enum.all?(diagnostics, &(&1.source == "elmc/manifest"))
  end

  test "watch app templates produce strict CoreIR artifacts" do
    templates = ["game-2048", "game-basic", "starter", "watchface-digital"]

    for template <- templates do
      workspace_root = tmp_workspace_path("strict-coreir-#{template}")

      on_exit(fn -> File.rm_rf(workspace_root) end)

      assert :ok = ProjectTemplates.apply_template(template, workspace_root)

      project_dir =
        case File.exists?(Path.join(workspace_root, "watch/elm.json")) do
          true -> Path.join(workspace_root, "watch")
          false -> workspace_root
        end

      assert {:ok, project} = ElmEx.Frontend.Bridge.load_project(project_dir)
      assert {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)
      assert {:ok, core_ir} = ElmEx.CoreIR.from_ir(ir, strict?: true)
      assert core_ir.version == "elm_ex.core_ir.v1"
    end
  end

  test "compile attaches strict CoreIR metadata for normal watch templates" do
    for template <- ["game-2048", "starter"] do
      workspace_root = tmp_workspace_path("compile-strict-coreir-#{template}")

      on_exit(fn -> File.rm_rf(workspace_root) end)

      assert :ok = ProjectTemplates.apply_template(template, workspace_root)

      assert {:ok, result} =
               Compiler.compile("compile-strict-coreir-#{template}",
                 workspace_root: workspace_root
               )

      assert result.status == :ok
      assert is_binary(result.elm_executor_core_ir_b64)
      assert get_in(result, [:elm_executor_metadata, "core_ir_validation"]) == "strict"
    end
  end

  test "compiled 2048 template evaluates merge button updates" do
    workspace_root = tmp_workspace_path("compile-2048-merge")
    on_exit(fn -> File.rm_rf(workspace_root) end)

    assert :ok = ProjectTemplates.apply_template("game-2048", workspace_root)

    assert {:ok, result} =
             Compiler.compile("compile-2048-merge",
               workspace_root: workspace_root
             )

    assert {:ok, binary} = Base.decode64(result.elm_executor_core_ir_b64)
    core_ir = :erlang.binary_to_term(binary, [:safe])

    source = File.read!(Path.join([workspace_root, "watch", "src", "Main.elm"]))

    current_model = %{
      "runtime_model" => %{
        "cells" => [2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "score" => 0,
        "best" => 0,
        "seed" => 12_345,
        "turn" => 0
      }
    }

    assert {:ok, step} =
             SemanticExecutor.execute(%{
               source_root: "watch",
               rel_path: "watch/src/Main.elm",
               source: source,
               introspect: %{},
               current_model: current_model,
               current_view_tree: %{},
               message: "LeftPressed",
               elm_executor_core_ir: core_ir
             })

    model = step.model_patch["runtime_model"]
    assert model["score"] == 4
    assert model["best"] == 4
    assert model["turn"] == 1
    assert List.first(model["cells"]) == 4
    assert step.runtime["operation_source"] == "core_ir_update_eval"
  end

  defp tmp_workspace_path(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
  end
end
