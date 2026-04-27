defmodule Ide.PublishManifest do
  @moduledoc """
  Exports publish bundle metadata linking PBW artifacts and screenshots.
  """

  @type export_result :: %{
          path: String.t(),
          payload: map()
        }
  @type release_notes_result :: %{path: String.t(), markdown: String.t()}

  @doc """
  Writes a publish manifest JSON file for a project.
  """
  @spec export(String.t(), keyword()) :: {:ok, export_result()} | {:error, term()}
  def export(project_slug, opts) do
    with {:ok, output_root} <- output_root(),
         :ok <- File.mkdir_p(Path.join(output_root, project_slug)) do
      artifact_path = Keyword.get(opts, :artifact_path)
      screenshot_groups = Keyword.get(opts, :screenshot_groups, [])
      required_targets = Keyword.get(opts, :required_targets, [])
      readiness = Keyword.get(opts, :readiness, [])

      payload = %{
        schema_version: 1,
        project_slug: project_slug,
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        artifact: %{
          pbw_path: artifact_path,
          exists: is_binary(artifact_path) and File.exists?(artifact_path)
        },
        required_targets: required_targets,
        readiness: readiness,
        screenshots_by_target:
          Enum.map(screenshot_groups, fn {target, shots} ->
            %{
              target: target,
              screenshots:
                Enum.map(shots, fn shot ->
                  %{
                    filename: shot.filename,
                    url: shot.url,
                    absolute_path: shot.absolute_path,
                    captured_at: shot.captured_at
                  }
                end)
            }
          end)
      }

      filename = "publish-bundle-#{timestamp()}.json"
      path = Path.join([output_root, project_slug, filename])

      :ok = File.write(path, Jason.encode!(payload, pretty: true))

      {:ok, %{path: path, payload: payload}}
    end
  rescue
    error -> {:error, error}
  end

  @doc """
  Writes a release notes draft markdown file for a project.
  """
  @spec export_release_notes(String.t(), String.t()) ::
          {:ok, release_notes_result()} | {:error, term()}
  def export_release_notes(project_slug, markdown) do
    with {:ok, output_root} <- output_root(),
         :ok <- File.mkdir_p(Path.join(output_root, project_slug)) do
      filename = "release-notes-#{timestamp()}.md"
      path = Path.join([output_root, project_slug, filename])
      :ok = File.write(path, markdown)
      {:ok, %{path: path, markdown: markdown}}
    end
  rescue
    error -> {:error, error}
  end

  @spec output_root() :: term()
  defp output_root do
    path =
      Application.get_env(:ide, Ide.PublishManifest, [])
      |> Keyword.get(:output_root)

    if is_binary(path), do: {:ok, path}, else: {:error, :publish_manifest_output_not_configured}
  end

  @spec timestamp() :: term()
  defp timestamp do
    DateTime.utc_now()
    |> DateTime.to_iso8601(:basic)
    |> String.replace(["-", ":", "T", "Z"], "")
  end
end
