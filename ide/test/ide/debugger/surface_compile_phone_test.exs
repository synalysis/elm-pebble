defmodule Ide.Debugger.SurfaceCompilePhoneTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.SurfaceCompileArtifacts
  alias Ide.Projects

  test "phone workspace entrypoint artifacts attach versioned core ir for companion templates" do
    slug = "surface-compile-phone-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "Surface compile phone",
               "slug" => slug,
               "target_type" => "companion",
               "template" => "companion-demo-phone-status"
             })

    artifacts = SurfaceCompileArtifacts.entrypoint_artifacts(slug, project, "phone")

    assert is_binary(artifacts["elm_executor_core_ir_b64"]) and
             artifacts["elm_executor_core_ir_b64"] != ""

    assert RuntimeArtifacts.versioned_core_ir?(%{
             "elm_executor_core_ir_b64" => artifacts["elm_executor_core_ir_b64"]
           })

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

    assert "CompanionApp" in module_names
  end
end
