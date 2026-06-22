defmodule IdeWeb.WorkspaceLive.DebuggerPreview.Hydration do
  @moduledoc false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Projects.Project
  alias Ide.Resources.{ApngProbe, ApngStaticPreview, PdcDecoder, ResourceStore}
  alias IdeWeb.WorkspaceLive.DebuggerPreview.SvgOps
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: PreviewTypes

  @type svg_op :: PreviewTypes.svg_op()
  @type animation_hydration_fields :: PreviewTypes.animation_hydration_fields()
  @type resource_ctor_ref :: PreviewTypes.resource_ctor_ref()

  @spec hydrate_vector_svg_ops([svg_op()], Project.t() | nil) :: [svg_op()]
  def hydrate_vector_svg_ops(rows, %Project{} = project) when is_list(rows) do
    indices = RuntimeArtifacts.vector_resource_indices_for_project(project.slug)

    rows
    |> Enum.map(&resolve_vector_svg_op_id(&1, indices))
    |> Enum.flat_map(fn
      %{kind: :vector_at, vector_id: vector_id, x: x, y: y} when vector_id >= 1 ->
        hydrate_static_vector(project, vector_id, x, y)

      %{kind: :vector_sequence_at, animation_id: animation_id, vector_id: vector_id, x: x, y: y}
      when vector_id >= 1 ->
        hydrate_vector_sequence(project, animation_id || 0, vector_id, x, y)

      %{kind: kind, vector_id: 0} when kind in [:vector_at, :vector_sequence_at] ->
        []

      other ->
        [other]
    end)
  end

  def hydrate_vector_svg_ops(rows, _project) when is_list(rows), do: rows

  @spec resolve_vector_svg_op_id(svg_op(), PreviewTypes.resource_index_map()) :: svg_op()
  def resolve_vector_svg_op_id(%{kind: kind} = op, indices)
      when kind in [:vector_at, :vector_sequence_at] and is_map(indices) do
    case Map.get(op, :vector_id) do
      id when is_integer(id) and id > 0 ->
        op

      _ ->
        resource = Map.get(op, :resource) || Map.get(op, "resource")
        id = vector_resource_index(resource, indices)
        if id > 0, do: Map.put(op, :vector_id, id), else: op
    end
  end

  def resolve_vector_svg_op_id(op, _indices), do: op

  @spec resolve_bitmap_svg_ops([svg_op()], Project.t() | PreviewTypes.runtime_input()) ::
          [svg_op()]
  defdelegate resolve_bitmap_svg_ops(rows, runtime_or_project), to: SvgOps

  @spec hydrate_animation_svg_ops([svg_op()], Project.t() | nil) :: [svg_op()]
  def hydrate_animation_svg_ops(rows, %Project{} = project) when is_list(rows) do
    Enum.map(rows, fn
      %{kind: :bitmap_sequence_at, animation_id: playback_id, bitmap_animation_id: resource_id, x: x, y: y} = row
      when resource_id >= 1 ->
        case animation_preview_op(project, resource_id, playback_id, x, y) do
          %{} = hydrated -> Map.merge(row, hydrated)
          nil -> row
        end

      other ->
        other
    end)
  end

  def hydrate_animation_svg_ops(rows, _project) when is_list(rows), do: rows

  @spec vector_resource_index(resource_ctor_ref(), PreviewTypes.resource_index_map()) ::
          non_neg_integer()
  defp vector_resource_index(resource, indices) when is_map(indices) do
    name = vector_resource_name(resource)

    case Map.get(indices, name) || Map.get(indices, String.to_atom(name)) do
      id when is_integer(id) and id > 0 -> id
      _ -> 0
    end
  end

  @spec vector_resource_name(resource_ctor_ref()) :: String.t()
  defp vector_resource_name(resource) when is_binary(resource), do: resource
  defp vector_resource_name(resource) when is_atom(resource), do: Atom.to_string(resource)
  defp vector_resource_name(%{"ctor" => ctor}), do: to_string(ctor)
  defp vector_resource_name(%{ctor: ctor}), do: to_string(ctor)
  defp vector_resource_name(_), do: ""

  @spec animation_preview_op(Project.t(), pos_integer(), integer(), integer(), integer()) ::
          animation_hydration_fields() | nil
  defp animation_preview_op(project, resource_id, playback_id, x, y) do
    with {:ok, path} <- ResourceStore.animation_file_path_by_id(project, resource_id),
         {:ok, bytes} <- File.read(path),
         {:ok, probe} <- ApngProbe.probe_bytes(bytes),
         {:ok, preview_bytes} <- ApngStaticPreview.static_png_bytes(bytes) do
      href = "data:image/png;base64," <> Base.encode64(preview_bytes)

      play_count =
        case probe.play_count do
          :infinite -> 0
          count when is_integer(count) -> count
        end

      %{
        href: href,
        width: probe.width,
        height: probe.height,
        play_count: play_count,
        anim_id: bitmap_sequence_anim_id(playback_id, resource_id, x, y)
      }
    else
      _ -> nil
    end
  end

  @spec bitmap_sequence_anim_id(integer(), pos_integer(), integer(), integer()) :: String.t()
  defp bitmap_sequence_anim_id(playback_id, resource_id, x, y),
    do: "debugger-bseq-#{playback_id}-#{resource_id}-#{x}-#{y}"

  @spec hydrate_static_vector(Project.t(), pos_integer(), integer(), integer()) :: [svg_op()]
  defp hydrate_static_vector(project, vector_id, x, y) do
    case read_vector_bytes(project, vector_id) do
      {:ok, bytes} ->
        case PdcDecoder.decode(bytes) do
          {:ok, image} ->
            PdcDecoder.to_debugger_ops(image, x, y)

          _ ->
            [unresolved_vector_op("vector_at", vector_id)]
        end

      _ ->
        [unresolved_vector_op("vector_at", vector_id)]
    end
  end

  @spec hydrate_vector_sequence(Project.t(), integer(), pos_integer(), integer(), integer()) ::
          [svg_op()]
  defp hydrate_vector_sequence(project, animation_id, vector_id, x, y) do
    case read_vector_bytes(project, vector_id) do
      {:ok, bytes} ->
        case PdcDecoder.decode_sequence(bytes) do
          {:ok, sequence} when sequence.frames != [] ->
            [
              %{
                kind: :vector_sequence_anim,
                anim_id: vector_sequence_anim_id(animation_id, vector_id, x, y),
                vector_id: vector_id,
                x: x,
                y: y,
                width: abs(sequence.width),
                height: abs(sequence.height),
                play_count: sequence.play_count,
                durations: Enum.map(sequence.frames, & &1.duration_ms),
                frame_elements:
                  Enum.map(sequence.frames, fn %{image: image} ->
                    PdcDecoder.to_svg_elements(image)
                  end)
              }
            ]

          {:ok, _sequence} ->
            hydrate_static_vector(project, vector_id, x, y)

          _ ->
            case PdcDecoder.decode_sequence_frame(bytes, 0) do
              {:ok, image} ->
                PdcDecoder.to_debugger_ops(image, x, y)

              _ ->
                [unresolved_vector_op("vector_sequence_at", vector_id)]
            end
        end

      _ ->
        [unresolved_vector_op("vector_sequence_at", vector_id)]
    end
  end

  @spec read_vector_bytes(Project.t(), pos_integer()) ::
          {:ok, binary()} | {:error, File.posix() | atom()}
  defp read_vector_bytes(project, vector_id) do
    with {:ok, path} <- ResourceStore.vector_file_path_by_id(project, vector_id),
         {:ok, bytes} <- File.read(path) do
      {:ok, bytes}
    end
  end

  @spec unresolved_vector_op(String.t(), pos_integer()) :: svg_op()
  defp unresolved_vector_op(node_type, vector_id) do
    %{
      kind: :unresolved,
      node_type: node_type,
      vector_id: vector_id,
      provided_int_count: 3,
      required_int_count: 3
    }
  end

  @spec vector_sequence_anim_id(integer(), pos_integer(), integer(), integer()) :: String.t()
  defp vector_sequence_anim_id(animation_id, vector_id, x, y),
    do: "debugger-vseq-#{animation_id}-#{vector_id}-#{x}-#{y}"
end
