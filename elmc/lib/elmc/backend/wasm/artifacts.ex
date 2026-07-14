defmodule Elmc.Backend.Wasm.Artifacts do
  @moduledoc """
  Summarize WASM build artifacts for compile results and tests.
  """

  alias Elmc.Backend.Wasm.ProjectWriter

  @type summary ::
          %{
            available: true,
            contract: String.t() | nil,
            version: integer() | nil,
            manifest_path: String.t(),
            wat_path: String.t() | nil,
            function_count: non_neg_integer(),
            skipped_count: non_neg_integer(),
            pruned_count: non_neg_integer(),
            imports: [String.t()],
            plan_toolchain: map() | nil,
            plan_coverage: map() | nil,
            functions: [map()],
            skipped: [map()]
          }
          | %{available: false, reason: String.t() | nil}
          | %{available: false}

  @spec read_summary(String.t()) :: summary()
  def read_summary(build_dir) when is_binary(build_dir) do
    path = ProjectWriter.manifest_path(build_dir)

    if File.regular?(path) do
      case File.read(path) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, manifest} -> summary_from_manifest(manifest, build_dir, path)
            {:error, reason} -> %{available: false, reason: inspect(reason)}
          end

        {:error, reason} ->
          %{available: false, reason: inspect(reason)}
      end
    else
      %{available: false}
    end
  end

  @spec summary_from_manifest(map(), String.t(), String.t()) :: summary()
  def summary_from_manifest(manifest, build_dir, path) when is_map(manifest) do
    functions = Map.get(manifest, "functions", [])
    skipped = Map.get(manifest, "skipped", [])

    %{
      available: true,
      contract: Map.get(manifest, "contract"),
      version: Map.get(manifest, "version"),
      manifest_path: path,
      wat_path: wat_path_if_present(build_dir, manifest),
      function_count: length(functions),
      skipped_count: length(skipped),
      pruned_count: Map.get(manifest, "pruned_count", 0),
      imports: Map.get(manifest, "imports", []),
      plan_toolchain: Map.get(manifest, "plan_toolchain"),
      plan_coverage: Map.get(manifest, "plan_coverage"),
      functions:
        Enum.map(functions, fn entry ->
          %{
            module: Map.get(entry, "module"),
            name: Map.get(entry, "name"),
            export: Map.get(entry, "export"),
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

  defp wat_path_if_present(build_dir, manifest) do
    case Map.get(manifest, "wat_file") do
      file when is_binary(file) ->
        path = Path.join([build_dir, "wasm", file])
        if File.regular?(path), do: path, else: nil

      _ ->
        nil
    end
  end
end
