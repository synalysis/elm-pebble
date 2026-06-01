defmodule Ide.Debugger.PokeBattleRuntimeModelTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger.CompileContract
  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Projects

  @template "watchface-poke-battle"

  test "init produces fully evaluated poke battle runtime model without parser artifacts" do
    slug = "poke-runtime-model-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Poke runtime model",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => @template
             })

    assert {:ok, source} = Projects.read_source_file(project, "watch", "src/Main.elm")

    artifacts = SurfaceCompileArtifacts.entrypoint_artifacts(slug, project, "watch")

    assert {:ok, snapshot} = CompileContract.analyze_source(source, "src/Main.elm")
    ei = Map.new(snapshot, fn {k, v} -> {to_string(k), v} end)

    launch_context = %{
      "screen" => %{"width" => 144, "height" => 168, "shape" => "Rectangular"},
      "reason" => "LaunchWakeup"
    }

    request =
      %{
        source_root: "watch",
        rel_path: "src/Main.elm",
        source: source,
        introspect: ei,
        current_model: %{"launch_context" => launch_context},
        current_view_tree: %{},
        message: nil
      }
      |> Map.merge(artifacts)
      |> Map.merge(RuntimeArtifacts.execution_artifacts(artifacts))

    assert {:ok, payload} = RuntimeExecutor.execute(request)

    runtime_model = payload.model_patch["runtime_model"]

    assert is_map(runtime_model["layout"]) and Map.has_key?(runtime_model["layout"], "boxX")
    assert is_map(runtime_model["player"]) and is_binary(runtime_model["player"]["displayName"])
    assert is_map(runtime_model["opponent"]) and Map.has_key?(runtime_model["opponent"], "x")
    assert is_boolean(runtime_model["animating"])
    assert %{"ctor" => _} = runtime_model["scene"]

    refute runtime_model_contains_parser_artifacts?(runtime_model)

    assert payload.view_output != []
    refute Enum.all?(payload.view_output, &(&1["kind"] == "unresolved"))
  end

  test "init rejects missing Core IR instead of returning parser init_model" do
    source =
      File.read!(
        Path.expand(
          "../../../priv/project_templates/watchface_poke_battle/src/Main.elm",
          __DIR__
        )
      )

    assert {:ok, snapshot} = CompileContract.analyze_source(source, "src/Main.elm")
    ei = Map.new(snapshot, fn {k, v} -> {to_string(k), v} end)

    request = %{
      source_root: "watch",
      rel_path: "src/Main.elm",
      source: source,
      introspect: ei,
      current_model: %{
        "launch_context" => %{
          "screen" => %{"width" => 144, "height" => 168, "shape" => "Rectangular"},
          "reason" => "LaunchWakeup"
        }
      },
      current_view_tree: %{},
      message: nil
    }

    assert {:error, {:core_ir_execution_failed, :missing_core_ir}} = RuntimeExecutor.execute(request)
  end

  test "init with Core IR does not keep parser init_model when introspect init_model has artifacts" do
    slug = "poke-parser-fallback-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Poke parser fallback",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => @template
             })

    assert {:ok, source} = Projects.read_source_file(project, "watch", "src/Main.elm")
    artifacts = SurfaceCompileArtifacts.entrypoint_artifacts(slug, project, "watch")
    assert {:ok, snapshot} = CompileContract.analyze_source(source, "src/Main.elm")
    ei = Map.new(snapshot, fn {k, v} -> {to_string(k), v} end)

    ei =
      Map.put(ei, "init_model", %{
        "layout" => %{"call" => "Render.layoutFor", "args" => [%{"$var" => "screenW"}]},
        "player" => %{
          "call" => "Pokemon.playerFromSpecies",
          "args" => [%{"$var" => "screenW"}, %{"ctor" => "Pikachu", "args" => []}]
        },
        "screenW" => 144
      })

    request =
      %{
        source_root: "watch",
        rel_path: "src/Main.elm",
        source: source,
        introspect: ei,
        current_model: %{
          "launch_context" => %{
            "screen" => %{"width" => 144, "height" => 168, "shape" => "Rectangular"},
            "reason" => "LaunchWakeup"
          }
        },
        current_view_tree: %{},
        message: nil
      }
      |> Map.merge(artifacts)
      |> Map.merge(RuntimeArtifacts.execution_artifacts(artifacts))

    assert {:ok, payload} = RuntimeExecutor.execute(request)
    refute runtime_model_contains_parser_artifacts?(payload.model_patch["runtime_model"])
  end

  defp runtime_model_contains_parser_artifacts?(value) when is_map(value) do
    Map.has_key?(value, "$var") or Map.has_key?(value, "$opaque") or Map.has_key?(value, "call") or
      Enum.any?(value, fn {_k, nested} -> runtime_model_contains_parser_artifacts?(nested) end)
  end

  defp runtime_model_contains_parser_artifacts?(value) when is_list(value),
    do: Enum.any?(value, &runtime_model_contains_parser_artifacts?/1)

  defp runtime_model_contains_parser_artifacts?(_), do: false
end
