defmodule Ide.Debugger.RuntimeArtifactsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Surface

  describe "inner_runtime_model/1" do
    test "extracts nested runtime_model from app or execution model" do
      app = %{"runtime_model" => %{"latitudeE6" => 0}, "status" => "idle"}
      execution = Map.merge(%{"elm_introspect" => %{}}, app)

      assert RuntimeArtifacts.inner_runtime_model(app) == %{"latitudeE6" => 0}
      assert RuntimeArtifacts.inner_runtime_model(execution) == %{"latitudeE6" => 0}
    end

    test "returns empty map when runtime_model is absent" do
      assert RuntimeArtifacts.inner_runtime_model(%{"status" => "idle"}) == %{}
    end
  end

  describe "decode_core_ir/1" do
    test "returns embedded map when present" do
      core_ir = %{"modules" => [%{"name" => "Main"}]}

      assert RuntimeArtifacts.decode_core_ir(%{"elm_executor_core_ir" => core_ir}) == core_ir
    end

    test "decodes base64 artifact" do
      core_ir = %{"modules" => [%{"name" => "Main"}]}
      encoded = Base.encode64(:erlang.term_to_binary(core_ir))

      assert RuntimeArtifacts.decode_core_ir(%{"elm_executor_core_ir_b64" => encoded}) == core_ir
    end

    test "decodes base64 CoreIR struct artifact" do
      {:ok, core_ir} =
        ElmEx.CoreIR.from_ir(%ElmEx.IR{
          modules: [
            %ElmEx.IR.Module{
              name: "Main",
              imports: [],
              declarations: [
                %ElmEx.IR.Declaration{
                  kind: :function,
                  name: "main",
                  args: [],
                  expr: %{op: :int_literal, value: 1},
                  ownership: []
                }
              ]
            }
          ]
        })

      encoded = Base.encode64(:erlang.term_to_binary(core_ir))

      assert %ElmEx.CoreIR{version: "elm_ex.core_ir.v1"} =
               RuntimeArtifacts.decode_core_ir(%{"elm_executor_core_ir_b64" => encoded})
    end
  end

  describe "strip_shell_artifacts/1 and public_model/1" do
    test "removes debugger shell keys from exported model view" do
      model = %{
        "count" => 1,
        "elm_introspect" => %{"module" => "Main"},
        "elm_executor_core_ir_b64" => "abc",
        "vector_resource_indices" => %{"Fog" => 1}
      }

      assert RuntimeArtifacts.strip_shell_artifacts(model) == %{"count" => 1}
      assert RuntimeArtifacts.public_model(model) == %{"count" => 1}
    end

    test "public_model prefers nested runtime_model" do
      model = %{
        "elm_introspect" => %{"module" => "Main"},
        "runtime_model" => %{"weather" => "fog"}
      }

      assert RuntimeArtifacts.public_model(model) == %{"weather" => "fog"}
    end
  end

  describe "normalize_surface/1 and introspect/1" do
    test "migrates legacy shell keys from model into shell" do
      surface = %{
        model: %{
          "count" => 1,
          "elm_introspect" => %{"module" => "Main"},
          "elm_executor_core_ir_b64" => "abc"
        }
      }

      normalized = RuntimeArtifacts.normalize_surface(surface)

      assert normalized.model == %{"count" => 1}
      assert normalized.shell["elm_introspect"] == %{"module" => "Main"}
      assert normalized.shell["elm_executor_core_ir_b64"] == "abc"
    end

    test "reads introspect from shell, not stripped app model" do
      surface = %{
        model: %{"runtime_model" => %{"latitudeE6" => 1}},
        shell: %{"elm_introspect" => %{"module" => "Main", "update_case_branches" => ["Tick"]}}
      }

      assert RuntimeArtifacts.introspect(surface) == %{
               "module" => "Main",
               "update_case_branches" => ["Tick"]
             }

      assert RuntimeArtifacts.introspect(surface.model) == nil
      assert RuntimeArtifacts.require_introspect(Surface.execution_model(surface))["module"] ==
               "Main"
    end
  end

  describe "merge_shell_artifacts/2" do
    test "copies shell artifact keys onto base runtime model" do
      base = %{"count" => 1}
      shell = %{"count" => 99, "elm_introspect" => %{"module" => "Main"}, "ignored" => true}

      assert RuntimeArtifacts.merge_shell_artifacts(base, shell) == %{
               "count" => 1,
               "elm_introspect" => %{"module" => "Main"}
             }
    end
  end

  describe "core_ir_eval_context/2" do
    test "includes vector resource indices and module name" do
      model = %{
        "elm_introspect" => %{"module" => "WeatherFace"},
        "vector_resource_indices" => %{"Fog" => 3}
      }

      ctx = RuntimeArtifacts.core_ir_eval_context(model)

      assert ctx.module == "WeatherFace"
      assert ctx.source_module == "WeatherFace"
      assert ctx.vector_resource_indices == %{"Fog" => 3}
    end

    test "merges optional extras" do
      model = %{"elm_introspect" => %{"module" => "Main"}}
      weather = %{"condition" => "fog"}

      ctx = RuntimeArtifacts.core_ir_eval_context(model, simulator_weather: weather)

      assert ctx.simulator_weather == weather
    end
  end
end
