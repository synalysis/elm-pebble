defmodule Elmc.Backend.Bytecode.Artifacts do
  @moduledoc """
  Summarize `.elmcbc` build artifacts for IDE/debugger surfaces.
  """

  alias Elmc.Backend.Bytecode.{Loader, ProjectWriter}
  alias Elmc.Backend.Bytecode.Artifacts.Types, as: ArtifactTypes

  @type summary :: ArtifactTypes.summary()
  @type function_row :: ArtifactTypes.function_row()
  @type skipped_row :: ArtifactTypes.skipped_row()
  @type manifest_function_entry :: ArtifactTypes.manifest_function_entry()
  @type wire_manifest :: ArtifactTypes.wire_manifest()

  @spec read_summary(String.t()) :: summary()
  def read_summary(build_dir) when is_binary(build_dir) do
    path = ProjectWriter.manifest_path(build_dir)

    if File.regular?(path) do
      case Loader.load_manifest(path) do
        {:ok, manifest} -> summary_from_manifest(manifest, path)
        {:error, reason} -> %{available: false, reason: inspect(reason)}
      end
    else
      %{available: false}
    end
  end

  @spec summary_from_manifest(ArtifactTypes.wire_manifest(), String.t()) :: summary()
  def summary_from_manifest(manifest, path) when is_map(manifest) do
    functions = Map.get(manifest, "functions", [])
    skipped = Map.get(manifest, "skipped", [])

    %{
      available: true,
      contract: Map.get(manifest, "contract"),
      version: Map.get(manifest, "version"),
      manifest_path: path,
      function_count: length(functions),
      skipped_count: length(skipped),
      pruned_count: Map.get(manifest, "pruned_count", 0),
      plan_toolchain: Map.get(manifest, "plan_toolchain"),
      plan_coverage: Map.get(manifest, "plan_coverage"),
      functions:
        Enum.map(functions, fn entry ->
          %{
            module: Map.get(entry, "module"),
            name: Map.get(entry, "name"),
            file: Map.get(entry, "file"),
            params: Map.get(entry, "params", [])
          }
        end),
      skipped:
        Enum.map(skipped, fn entry ->
          %{
            module: Map.get(entry, "module"),
            name: Map.get(entry, "name"),
            reason: Map.get(entry, "reason")
          }
        end)
    }
  end
end
