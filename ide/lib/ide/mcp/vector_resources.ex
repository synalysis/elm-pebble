defmodule Ide.Mcp.VectorResources do
  @moduledoc false

  alias Ide.Mcp.ConversionOpts
  alias Ide.Mcp.ToolTypes
  alias Ide.Mcp.Types
  alias Ide.Projects
  alias Ide.Resources.{ConversionReport, PdcDecoder, ResourceStore, SvgConverter}

  @vector_opts_schema ConversionOpts.schema()

  @spec list(String.t()) :: {:ok, Types.vector_tool_result()} | {:error, String.t()}
  def list(slug) when is_binary(slug) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, entries} <- Projects.list_vector_resources(project) do
      {:ok,
       %{
         "slug" => slug,
         "entries" =>
           Enum.map(entries, fn entry ->
             entry
             |> Map.new(fn {k, v} -> {to_string(k), v} end)
             |> Map.put_new("kind", "image")
           end)
       }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  @spec convert(ToolTypes.tool_args()) :: {:ok, Types.vector_tool_result()} | {:error, String.t()}
  def convert(args) when is_map(args) do
    svg = Map.get(args, "svg") || Map.get(args, :svg)
    opts = ConversionOpts.from_args(args)

    with true <- is_binary(svg) and svg != "",
         {:ok, result} <- SvgConverter.convert_svg_string(svg, opts) do
      {:ok,
       %{
         "magic" => SvgConverter.pdc_magic(result.bytes),
         "bytes_base64" => Base.encode64(result.bytes),
         "byte_size" => byte_size(result.bytes),
         "report" => ConversionReport.to_map(result.report)
       }}
    else
      false -> {:error, "svg is required"}
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  @spec convert_sequence(ToolTypes.tool_args()) ::
          {:ok, Types.vector_tool_result()} | {:error, String.t()}
  def convert_sequence(args) when is_map(args) do
    frames = Map.get(args, "frames") || Map.get(args, :frames) || []
    opts = ConversionOpts.from_args(args)

    with true <- is_list(frames) and frames != [],
         {:ok, result} <- SvgConverter.convert_svg_sequence(frames, opts) do
      {:ok,
       %{
         "magic" => SvgConverter.pdc_magic(result.bytes),
         "bytes_base64" => Base.encode64(result.bytes),
         "byte_size" => byte_size(result.bytes),
         "frame_count" => length(frames),
         "report" => ConversionReport.to_map(result.report)
       }}
    else
      false -> {:error, "frames must be a non-empty list of svg strings"}
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  @spec import(ToolTypes.tool_args()) :: {:ok, Types.vector_tool_result()} | {:error, String.t()}
  def import(args) when is_map(args) do
    slug = Map.get(args, "slug") || Map.get(args, :slug)
    svg = Map.get(args, "svg") || Map.get(args, :svg)
    name = Map.get(args, "name") || Map.get(args, :name) || "vector.svg"
    opts = ConversionOpts.from_args(args)

    with {:ok, project} <- fetch_project(slug),
         true <- is_binary(svg) and svg != "",
         {:ok, tmp} <- write_temp_svg(svg),
         {:ok, result} <- ResourceStore.import_vector_svg(project, tmp, name, opts) do
      File.rm(tmp)
      {:ok, import_payload(result)}
    else
      false -> {:error, "svg is required"}
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  @spec import_sequence(ToolTypes.tool_args()) ::
          {:ok, Types.vector_tool_result()} | {:error, String.t()}
  def import_sequence(args) when is_map(args) do
    slug = Map.get(args, "slug") || Map.get(args, :slug)
    frames = Map.get(args, "frames") || Map.get(args, :frames) || []
    name = Map.get(args, "name") || Map.get(args, :name) || "sequence.pdc"
    opts = ConversionOpts.from_args(args)

    with {:ok, project} <- fetch_project(slug),
         true <- is_list(frames) and frames != [],
         {:ok, result} <- ResourceStore.import_vector_sequence(project, frames, name, opts) do
      {:ok, import_payload(result)}
    else
      false -> {:error, "frames must be a non-empty list of svg strings"}
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  @spec preview(ToolTypes.tool_args()) :: {:ok, Types.vector_tool_result()} | {:error, String.t()}
  def preview(args) when is_map(args) do
    slug = Map.get(args, "slug")
    ctor = Map.get(args, "ctor")
    bytes_b64 = Map.get(args, "bytes_base64")
    frame = Map.get(args, "frame") || 0

    cond do
      is_binary(slug) and is_binary(ctor) ->
        with {:ok, project} <- fetch_project(slug),
             {:ok, path} <- ResourceStore.vector_file_path(project, ctor),
             {:ok, bytes} <- File.read(path) do
          preview_bytes(bytes, frame)
        else
          {:error, reason} -> {:error, format_error(reason)}
        end

      is_binary(bytes_b64) ->
        preview_bytes(Base.decode64!(bytes_b64), frame)

      true ->
        {:error, "provide slug+ctor or bytes_base64"}
    end
  end

  @spec delete(ToolTypes.tool_args()) :: {:ok, Types.vector_tool_result()} | {:error, String.t()}
  def delete(%{"slug" => slug, "ctor" => ctor}) when is_binary(slug) and is_binary(ctor) do
    with {:ok, project} <- fetch_project(slug),
         {:ok, entries} <- ResourceStore.delete_vector(project, ctor) do
      {:ok, %{"slug" => slug, "deleted" => ctor, "entries" => entries}}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  def delete(_), do: {:error, "slug and ctor are required"}

  @spec opts_schema() :: ConversionOpts.schema_map()
  def opts_schema, do: @vector_opts_schema

  defp preview_bytes(bytes, frame) do
    case SvgConverter.pdc_magic(bytes) do
      "PDCS" ->
        case PdcDecoder.decode_sequence_frame(bytes, frame) do
          {:ok, image} ->
            {:ok, %{"svg" => PdcDecoder.to_svg(image), "frame" => frame, "kind" => "sequence"}}

          {:error, reason} ->
            {:error, format_error(reason)}
        end

      "PDCI" ->
        case PdcDecoder.decode(bytes) do
          {:ok, image} ->
            {:ok, %{"svg" => PdcDecoder.to_svg(image), "frame" => 0, "kind" => "image"}}

          {:error, reason} ->
            {:error, format_error(reason)}
        end

      _ ->
        {:error, "invalid pdc bytes"}
    end
  end

  defp import_payload(%{duplicate: true} = result) do
    %{
      "duplicate" => true,
      "entry" => Map.get(result, :entry),
      "report" => report_map(result)
    }
  end

  defp import_payload(result) do
    %{
      "entry" => Map.get(result, :entry),
      "entries" => Map.get(result, :entries),
      "preview_svg" => Map.get(result, :preview_svg),
      "report" => report_map(result)
    }
  end

  defp report_map(result) do
    case Map.get(result, :report) do
      %ConversionReport{} = report -> ConversionReport.to_map(report)
      _ -> nil
    end
  end

  defp write_temp_svg(svg) do
    path = Path.join(System.tmp_dir!(), "mcp_vector_#{System.unique_integer([:positive])}.svg")

    case File.write(path, svg) do
      :ok -> {:ok, path}
      error -> error
    end
  end

  defp fetch_project(slug) do
    case Projects.get_project_by_scope_key(slug) do
      nil -> {:error, "project not found"}
      project -> {:ok, project}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
