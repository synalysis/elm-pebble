defmodule Ide.Resources.ResourceStore.Manifest do
  @moduledoc false

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Resources.ResourceStore.{GeneratedModule, Migration}
  alias Ide.Resources.Types

  @manifest_rel_path "watch/resources/bitmaps.json"
  @font_manifest_rel_path "watch/resources/fonts.json"
  @vector_manifest_rel_path "watch/resources/vectors.json"
  @animation_manifest_rel_path "watch/resources/animations.json"
  @generated_module_rel_path "watch/src/Pebble/Ui/Resources.elm"
  @legacy_generated_module_rel_path "watch/src/Pebble/Ui/Bitmap.elm"

  @spec manifest_rel_path() :: String.t()
  def manifest_rel_path, do: @manifest_rel_path

  @spec generated_module_rel_path() :: String.t()
  def generated_module_rel_path, do: @generated_module_rel_path

  @spec ensure_generated(Project.t()) :: :ok | {:error, Types.resource_error()}
  def ensure_generated(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with :ok <- Migration.migrate_all(workspace) do
      write_generated_module(workspace)
    end
  end

  @spec ensure_generated_workspace(Types.workspace_path()) :: :ok | {:error, Types.resource_error()}
  def ensure_generated_workspace(workspace) when is_binary(workspace) do
    with :ok <- Migration.migrate_all(workspace) do
      write_generated_module(workspace)
    end
  end

  @spec read_bitmap_manifest(Types.workspace_path()) ::
          {:ok, Types.manifest()} | {:error, Types.resource_error()}
  def read_bitmap_manifest(workspace) do
    workspace
    |> Path.join(@manifest_rel_path)
    |> read_manifest(strict: true)
  end

  @spec read_font_manifest(Types.workspace_path()) ::
          {:ok, Types.manifest()} | {:error, Types.resource_error()}
  def read_font_manifest(workspace) do
    workspace
    |> Path.join(@font_manifest_rel_path)
    |> read_manifest()
  end

  @spec read_vector_manifest(Types.workspace_path()) ::
          {:ok, Types.manifest()} | {:error, Types.resource_error()}
  def read_vector_manifest(workspace) do
    workspace
    |> Path.join(@vector_manifest_rel_path)
    |> read_manifest()
  end

  @spec read_animation_manifest(Types.workspace_path(), keyword()) ::
          {:ok, Types.manifest()} | {:error, Types.resource_error() | :invalid_manifest}
  def read_animation_manifest(workspace, opts \\ []) when is_binary(workspace) do
    workspace
    |> Path.join(@animation_manifest_rel_path)
    |> read_manifest(opts)
  end

  @spec write_manifest(Path.t(), Types.manifest()) :: :ok | {:error, Types.manifest_io_error()}
  def write_manifest(path, payload) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, json} <- Jason.encode(payload, pretty: true),
         :ok <- File.write(path, json <> "\n") do
      :ok
    end
  end

  @spec write_generated_module(Types.workspace_path()) :: :ok | {:error, Types.resource_error()}
  def write_generated_module(workspace) do
    bitmap_entries =
      case read_bitmap_manifest(workspace) do
        {:ok, manifest} -> manifest["entries"] || []
        _ -> []
      end

    font_entries =
      case read_font_manifest(workspace) do
        {:ok, manifest} -> manifest["entries"] || []
        _ -> []
      end

    vector_entries =
      case read_vector_manifest(workspace) do
        {:ok, manifest} ->
          file_backed_entries(workspace, "watch/resources/vectors", manifest["entries"] || [])

        _ ->
          []
      end

    animation_entries =
      case read_animation_manifest(workspace) do
        {:ok, manifest} ->
          file_backed_entries(workspace, "watch/resources/animations", manifest["entries"] || [])

        _ ->
          []
      end

    path = Path.join(workspace, @generated_module_rel_path)
    legacy = Path.join(workspace, @legacy_generated_module_rel_path)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <-
           File.write(
             path,
             GeneratedModule.source(
               bitmap_entries,
               font_entries,
               vector_entries,
               animation_entries
             )
           ) do
      _ = File.rm(legacy)
      :ok
    end
  end

  @spec read_manifest(Path.t(), keyword()) ::
          {:ok, Types.manifest()} | {:error, Types.manifest_io_error()}
  def read_manifest(path, opts \\ []) do
    path = Path.expand(path)
    strict? = Keyword.get(opts, :strict, false)

    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, decoded} when is_map(decoded) ->
            {:ok, Map.put_new(decoded, "entries", [])}

          _ ->
            if strict?,
              do: {:error, :invalid_manifest},
              else: {:ok, %{"schema_version" => 1, "entries" => []}}
        end

      {:error, :enoent} ->
        {:ok, %{"schema_version" => 1, "entries" => []}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec file_backed_entries(Types.workspace_path(), String.t(), [Types.manifest_wire_row()]) ::
          [Types.manifest_wire_row()]
  defp file_backed_entries(workspace, assets_rel_dir, entries) when is_list(entries) do
    assets_root = Path.join(workspace, assets_rel_dir)

    Enum.filter(entries, fn row ->
      filename = to_string(Map.get(row, "filename", ""))
      filename != "" and File.exists?(Path.join(assets_root, filename))
    end)
  end
end
