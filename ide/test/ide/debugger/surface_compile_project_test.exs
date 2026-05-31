defmodule Ide.Debugger.SurfaceCompileProjectTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Projects

  test "project workspace entrypoint artifacts attach versioned core ir when strict compile omits it" do
    slug = "surface-compile-project-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Surface compile project",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-poke-battle"
             })

    artifacts = SurfaceCompileArtifacts.entrypoint_artifacts(slug, project, "watch")

    assert is_binary(artifacts["elm_executor_core_ir_b64"]) and
             artifacts["elm_executor_core_ir_b64"] != ""

    assert RuntimeArtifacts.versioned_core_ir?(%{
             "elm_executor_core_ir_b64" => artifacts["elm_executor_core_ir_b64"]
           })
  end

  test "project entrypoint artifacts win over inline ephemeral compile for multi-module reload" do
    slug = "surface-compile-priority-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Surface compile priority",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-poke-battle"
             })

    assert {:ok, source} = Projects.read_source_file(project, "watch", "src/Main.elm")

    state = %{
      scope_key: slug,
      watch: %{
        model: %{
          "last_source" => source,
          "last_path" => "src/Main.elm",
          "source_root" => "watch"
        },
        shell: %{}
      }
    }

    ctx = %{
      session_key_from_state: fn _ -> slug end,
      source_root_for_target: fn :watch -> "watch" end,
      merge_runtime_artifacts: fn st, target, fields ->
        Ide.Debugger.RuntimeArtifactMerge.maybe_merge(st, target, fields)
      end
    }

    artifacts = SurfaceCompileArtifacts.artifacts_for_source_root(state, "watch", ctx)

    assert is_binary(artifacts["elm_executor_core_ir_b64"]) and
             artifacts["elm_executor_core_ir_b64"] != ""

    core_ir =
      artifacts["elm_executor_core_ir_b64"]
      |> Base.decode64!()
      |> :erlang.binary_to_term()

    module_names =
      (Map.get(core_ir, :modules) || Map.get(core_ir, "modules") || [])
      |> List.wrap()
      |> Enum.map(fn mod ->
        mod |> Map.get("name") |> then(fn
          nil -> Map.get(mod, :name)
          name -> name
        end)
      end)
      |> Enum.map(&to_string/1)

    assert "Pokemon" in module_names
    assert "Render" in module_names
  end
end
