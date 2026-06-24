defmodule IdeWeb.WorkspaceLive.DebuggerPage.SpeakerSamples do
  @moduledoc false

  alias Ide.Projects.Project
  alias Ide.Resources.Types, as: ResourceTypes

  @spec json(Project.t() | nil, [ResourceTypes.speaker_sample_entry()]) :: String.t()
  def json(%Project{} = project, samples) when is_list(samples) do
    samples
    |> Enum.map(&wire_row(project, &1))
    |> Jason.encode!([])
  end

  def json(_project, _samples), do: "[]"

  defp wire_row(project, row) when is_map(row) do
    filename = to_string(Map.get(row, :filename) || Map.get(row, "filename") || "")

    %{
      "index" => Map.get(row, :resource_id) || Map.get(row, "resource_id") || 0,
      "url" => sample_url(project, filename),
      "format" => Map.get(row, :format) || Map.get(row, "format") || 1,
      "base_midi_note" => Map.get(row, :base_midi_note) || Map.get(row, "base_midi_note") || 60,
      "loop" => Map.get(row, :loop) || Map.get(row, "loop") || false
    }
  end

  defp sample_url(%Project{slug: slug}, filename) when is_binary(filename) and filename != "" do
    "/projects/#{slug}/speaker_samples/#{URI.encode(filename)}"
  end

  defp sample_url(_project, _filename), do: ""
end
