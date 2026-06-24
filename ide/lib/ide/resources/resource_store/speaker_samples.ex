defmodule Ide.Resources.ResourceStore.SpeakerSamples do
  @moduledoc false

  alias Ide.Projects
  alias Ide.Projects.Project
  alias Ide.Resources.{CtorNaming, Types}
  alias Ide.Resources.ResourceStore.{Coercion, Duplicates, Manifest, SpeakerGeneratedModule}

  @manifest_rel_path "watch/resources/speaker_samples.json"
  @assets_rel_dir "watch/resources/speaker_samples"
  @generated_module_rel_path "watch/src/Pebble/Speaker/Resources.elm"
  @max_total_bytes 16 * 1024

  @spec list_samples(Project.t()) :: {:ok, [map()]} | {:error, Types.resource_error()}
  def list_samples(%Project{} = project) do
    workspace = Projects.project_workspace_path(project)

    with {:ok, manifest} <- read_manifest(workspace) do
      {:ok, file_backed_entries(workspace, manifest["entries"] || [])}
    end
  end

  @spec import_sample(Project.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def import_sample(%Project{} = project, upload_path, original_name, opts \\ [])
      when is_binary(upload_path) and is_binary(original_name) do
    workspace = Projects.project_workspace_path(project)
    assets_dir = Path.join(workspace, @assets_rel_dir)
    manifest_path = Path.join(workspace, @manifest_rel_path)

    with {:ok, bytes} <- File.read(upload_path),
         :ok <- validate_pcm_bytes(bytes),
         {:ok, safe_name} <- normalized_filename(original_name),
         {:ok, manifest} <- read_manifest(workspace),
         nil <- Duplicates.duplicate_asset_entry(manifest["entries"] || [], assets_dir, bytes),
         unique_ctor =
           CtorNaming.unique_ctor(:speaker_sample, base_name(original_name), manifest["entries"] || []),
         :ok <- enforce_total_bytes(manifest["entries"] || [], byte_size(bytes)),
         :ok <- File.mkdir_p(assets_dir),
         :ok <- File.write(Path.join(assets_dir, safe_name), bytes) do
      format = Keyword.get(opts, :format, 1)
      base_midi_note = Keyword.get(opts, :base_midi_note, 60)
      loop? = Keyword.get(opts, :loop, false)

      entry = %{
        "id" => Ecto.UUID.generate(),
        "ctor" => unique_ctor,
        "base_name" => base_name(original_name),
        "filename" => safe_name,
        "mime" => "application/octet-stream",
        "bytes" => byte_size(bytes),
        "format" => format,
        "base_midi_note" => base_midi_note,
        "loop" => loop?
      }

      entries = (manifest["entries"] || []) ++ [entry]
      payload = %{"schema_version" => 1, "entries" => entries}

      with :ok <- Manifest.write_manifest(manifest_path, payload),
           :ok <- write_generated_module(workspace) do
        {:ok, %{entry: entry, entries: entries}}
      end
    else
      %{} = duplicate -> {:ok, %{duplicate: true, entry: duplicate}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec write_generated_module(Types.workspace_path()) :: :ok | {:error, Types.resource_error()}
  def write_generated_module(workspace) when is_binary(workspace) do
    entries =
      case read_manifest(workspace) do
        {:ok, manifest} -> file_backed_entries(workspace, manifest["entries"] || [])
        _ -> []
      end

    path = Path.join(workspace, @generated_module_rel_path)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, SpeakerGeneratedModule.source(entries)) do
      :ok
    end
  end

  @spec read_only_generated_module?(String.t(), String.t()) :: boolean()
  def read_only_generated_module?(source_root, rel_path)
      when is_binary(source_root) and is_binary(rel_path) do
    {normalize_source_root(source_root), normalize_editor_rel_path(rel_path)} ==
      {"watch", "src/Pebble/Speaker/Resources.elm"}
  end

  def read_only_generated_module?(_, _), do: false

  defp read_manifest(workspace) do
    workspace
    |> Path.join(@manifest_rel_path)
    |> Manifest.read_manifest()
  end

  defp file_backed_entries(workspace, entries) when is_list(entries) do
    assets_root = Path.join(workspace, @assets_rel_dir)

    Enum.filter(entries, fn row ->
      filename = to_string(Map.get(row, "filename", ""))
      filename != "" and File.exists?(Path.join(assets_root, filename))
    end)
  end

  defp validate_pcm_bytes(bytes) when is_binary(bytes) and byte_size(bytes) > 0 do
    if byte_size(bytes) <= @max_total_bytes do
      :ok
    else
      {:error, :speaker_sample_too_large}
    end
  end

  defp validate_pcm_bytes(_), do: {:error, :invalid_speaker_sample}

  defp enforce_total_bytes(entries, incoming_bytes) when is_list(entries) do
    total =
      Enum.reduce(entries, 0, fn row, acc ->
        acc + Coercion.integer_or_zero(Map.get(row, "bytes", 0))
      end)

    if total + incoming_bytes <= @max_total_bytes do
      :ok
    else
      {:error, :speaker_sample_total_too_large}
    end
  end

  defp normalized_filename(original_name) do
    ext = original_name |> Path.basename() |> Path.extname() |> String.downcase()

    if ext in [".pcm", ".raw", ".bin"] do
      {:ok, Path.basename(original_name)}
    else
      {:error, :unsupported_speaker_sample_type}
    end
  end

  defp base_name(original_name) do
    original_name
    |> Path.basename()
    |> Path.rootname()
    |> CtorNaming.normalize_base_name()
  end

  defp normalize_source_root("watch"), do: "watch"
  defp normalize_source_root(other) when is_binary(other), do: String.trim_trailing(other, "/")

  defp normalize_editor_rel_path(path) when is_binary(path),
    do: path |> String.trim_leading("/") |> String.trim_leading("watch/")
end
