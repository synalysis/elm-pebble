defmodule Ide.Resources.PdcDecoder do
  @moduledoc """
  Decodes Pebble Draw Command (PDCI) image binaries into paths and circles for preview.

  Format matches the bundled `svg2pdc.py` serializer.
  """

  @type point :: %{x: integer(), y: integer()}
  @type command ::
          %{
            kind: :path | :circle,
            open: boolean(),
            stroke_color: integer(),
            stroke_width: integer(),
            fill_color: integer(),
            points: [point()],
            radius: integer() | nil,
            precise: boolean()
          }
  @type image :: %{
          width: integer(),
          height: integer(),
          commands: [command()]
        }
  @type sequence_frame :: %{
          duration_ms: non_neg_integer(),
          image: image()
        }
  @type sequence :: %{
          width: integer(),
          height: integer(),
          play_count: non_neg_integer(),
          frames: [sequence_frame()]
        }
  @type decode_error :: :invalid_pdc | :unsupported_pdc_format
  @type watch_validate_error ::
          :invalid_pdc
          | :unsupported_pdc_format
          | :invalid_watch_pdc
          | :pdc_too_large
          | :pdc_dimensions_too_large
          | :pdc_too_many_frames

  @type debugger_op_kind ::
          :path_filled | :path_outline | :path_outline_open | :fill_circle | :circle

  @type debugger_op :: %{
          required(:kind) => debugger_op_kind(),
          optional(atom()) => integer() | [point()] | nil
        }

  @max_watch_bytes 65_536
  @max_watch_dimension 200
  @max_watch_frames 64

  @command_type_path 1
  @command_type_circle 2
  @command_type_precise_path 3

  @spec decode(binary()) :: {:ok, image()} | {:error, decode_error()}
  def decode(bytes) when is_binary(bytes) do
    with {:ok, payload} <- strip_file_header(bytes),
         {:ok, image} <- decode_image_payload(payload) do
      {:ok, image}
    end
  end

  @spec decode_sequence_frame(binary(), non_neg_integer()) ::
          {:ok, image()} | {:error, decode_error()}
  def decode_sequence_frame(bytes, frame_index \\ 0)
      when is_binary(bytes) and is_integer(frame_index) and frame_index >= 0 do
    with {:ok, payload} <- strip_file_header(bytes),
         {:ok, width, height, _play_count, _frame_count, rest} <- sequence_header(payload),
         {:ok, frame_payload, _rest} <- nth_sequence_frame(rest, frame_index),
         {:ok, commands, _rest} <- decode_commands(frame_payload) do
      {:ok, %{width: width, height: height, commands: commands}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec decode_sequence(binary()) :: {:ok, sequence()} | {:error, decode_error()}
  def decode_sequence(bytes) when is_binary(bytes) do
    case pdc_magic(bytes) do
      "PDCS" ->
        with {:ok, payload} <- strip_file_header(bytes),
             {:ok, width, height, play_count, frame_count, rest} <- sequence_header(payload),
             {:ok, frames, _rest} <- decode_sequence_frames(frame_count, rest, width, height, []) do
          {:ok,
           %{
             width: width,
             height: height,
             play_count: play_count,
             frames: frames
           }}
        else
          {:error, reason} -> {:error, reason}
        end

      "PDCI" ->
        case decode(bytes) do
          {:ok, %{width: width, height: height} = image} ->
            {:ok,
             %{
               width: width,
               height: height,
               play_count: 1,
               frames: [%{duration_ms: 0, image: image}]
             }}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, :unsupported_pdc_format}
    end
  end

  @spec to_svg(image(), keyword()) :: String.t()
  def to_svg(%{width: width, height: height} = image, opts \\ []) do
    scale = Keyword.get(opts, :scale, 1.0)
    w = max(round(width * scale), 1)
    h = max(round(height * scale), 1)
    body = to_svg_elements(image, opts)

    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{width} #{height}" width="#{w}" height="#{h}" role="img">
    #{body}
    </svg>
    """
    |> String.trim()
  end

  @spec to_svg_elements(image(), keyword()) :: String.t()
  def to_svg_elements(%{commands: commands}, opts \\ []) do
    scale = Keyword.get(opts, :scale, 1.0)

    commands
    |> Enum.map(&command_to_svg(&1, scale))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @spec to_debugger_ops(image(), integer(), integer()) :: [debugger_op()]
  def to_debugger_ops(%{commands: commands}, offset_x, offset_y)
      when is_integer(offset_x) and is_integer(offset_y) do
    Enum.flat_map(commands, &command_to_debugger_ops(&1, offset_x, offset_y))
  end

  @spec decode_canvas_size(binary(), :image | :sequence) ::
          {:ok, {integer(), integer()}} | {:error, decode_error()}
  def decode_canvas_size(bytes, _kind \\ :image) when is_binary(bytes) do
    result =
      case pdc_magic(bytes) do
        "PDCS" -> decode_sequence_frame(bytes, 0)
        _ -> decode(bytes)
      end

    case result do
      {:ok, %{width: width, height: height}} ->
        {:ok, {abs(width), abs(height)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec preview_svg(binary()) :: {:ok, String.t()} | {:error, decode_error()}
  def preview_svg(bytes) when is_binary(bytes) do
    case pdc_magic(bytes) do
      "PDCS" ->
        decode_sequence_frame(bytes, 0)
        |> then(fn
          {:ok, image} -> {:ok, to_svg(image)}
          error -> error
        end)

      _ ->
        case decode(bytes) do
          {:ok, image} -> {:ok, to_svg(image)}
          error -> error
        end
    end
  end

  defp pdc_magic(bytes) when byte_size(bytes) >= 4 do
    <<magic::binary-size(4), _rest::binary>> = bytes
    magic
  end

  defp pdc_magic(_), do: nil

  defp strip_file_header(<<magic::binary-size(4), size::32-little, rest::binary>>)
       when magic in ["PDCI", "PDCS"] do
    if byte_size(rest) >= size do
      {:ok, binary_part(rest, 0, size)}
    else
      {:error, :invalid_pdc}
    end
  end

  defp strip_file_header(_), do: {:error, :invalid_pdc}

  defp decode_image_payload(payload) when is_binary(payload) do
    with <<_version, _reserved, width::16-little-signed, height::16-little-signed, rest::binary>> <-
           payload,
         {:ok, commands, _rest} <- decode_commands(rest) do
      {:ok, %{width: width, height: height, commands: commands}}
    else
      _ -> {:error, :invalid_pdc}
    end
  end

  defp sequence_header(
         <<_version, _reserved, width::16-little-signed, height::16-little-signed,
           play_count::16-little, frame_count::16-little, rest::binary>>
       )
       when frame_count > 0 do
    {:ok, width, height, play_count, frame_count, rest}
  end

  defp sequence_header(_), do: {:error, :unsupported_pdc_format}

  defp decode_sequence_frames(0, rest, _width, _height, acc), do: {:ok, Enum.reverse(acc), rest}

  defp decode_sequence_frames(count, rest, width, height, acc) when count > 0 do
    with <<duration_ms::16-little, frame_rest::binary>> <- rest,
         {:ok, commands, trailing} <- decode_commands(frame_rest) do
      frame = %{
        duration_ms: duration_ms,
        image: %{width: width, height: height, commands: commands}
      }

      decode_sequence_frames(count - 1, trailing, width, height, [frame | acc])
    else
      _ -> {:error, :invalid_pdc}
    end
  end

  defp nth_sequence_frame(rest, 0) do
    with <<_duration::16-little, frame_rest::binary>> <- rest,
         {:ok, _commands, trailing} <- decode_commands(frame_rest) do
      {:ok, frame_rest, trailing}
    else
      _ -> {:error, :invalid_pdc}
    end
  end

  defp nth_sequence_frame(rest, frame_index) when frame_index > 0 do
    with <<_duration::16-little, frame_rest::binary>> <- rest,
         {:ok, _commands, trailing} <- decode_commands(frame_rest) do
      nth_sequence_frame(trailing, frame_index - 1)
    else
      _ -> {:error, :invalid_pdc}
    end
  end

  defp nth_sequence_frame(_rest, _frame_index), do: {:error, :unsupported_pdc_format}

  defp decode_commands(<<count::16-little, rest::binary>>) when count >= 0 do
    decode_command_list(count, rest, [])
  end

  defp decode_commands(_), do: {:error, :invalid_pdc}

  defp decode_command_list(0, rest, acc), do: {:ok, Enum.reverse(acc), rest}

  defp decode_command_list(count, rest, acc) do
    with {:ok, command, rest} <- decode_command(rest) do
      decode_command_list(count - 1, rest, [command | acc])
    end
  end

  defp decode_command(
         <<type, _reserved, stroke_color, stroke_width, fill_color, open, _unused,
           point_count::16-little, rest::binary>>
       )
       when type in [@command_type_path, @command_type_precise_path] do
    precise = type == @command_type_precise_path
    point_size = if precise, do: 8, else: 4
    bytes_needed = point_count * point_size

    if byte_size(rest) >= bytes_needed do
      <<points_bin::binary-size(^bytes_needed), rest::binary>> = rest

      points =
        points_bin
        |> decode_points(point_count, precise)

      {:ok,
       %{
         kind: :path,
         open: open != 0,
         stroke_color: stroke_color,
         stroke_width: stroke_width,
         fill_color: fill_color,
         points: points,
         radius: nil,
         precise: precise
       }, rest}
    else
      {:error, :invalid_pdc}
    end
  end

  defp decode_command(
         <<@command_type_circle, _reserved, stroke_color, stroke_width, fill_color,
           radius::16-little, point_count::16-little, rest::binary>>
       )
       when point_count >= 1 do
    bytes_needed = point_count * 4

    if byte_size(rest) >= bytes_needed do
      <<points_bin::binary-size(^bytes_needed), rest::binary>> = rest
      [point | _] = decode_points(points_bin, point_count, false)

      {:ok,
       %{
         kind: :circle,
         open: false,
         stroke_color: stroke_color,
         stroke_width: stroke_width,
         fill_color: fill_color,
         points: [point],
         radius: radius,
         precise: false
       }, rest}
    else
      {:error, :invalid_pdc}
    end
  end

  defp decode_command(_), do: {:error, :invalid_pdc}

  defp decode_points(bin, count, precise) do
    decode_points(bin, count, precise, [])
  end

  defp decode_points(<<>>, 0, _precise, acc), do: Enum.reverse(acc)

  defp decode_points(
         <<x::16-little-signed, y::16-little-signed, rest::binary>>,
         count,
         false,
         acc
       ) do
    decode_points(rest, count - 1, false, [%{x: x, y: y} | acc])
  end

  defp decode_points(<<x::16-little-signed, y::16-little-signed, rest::binary>>, count, true, acc) do
    decode_points(rest, count - 1, true, [%{x: div(x, 8), y: div(y, 8)} | acc])
  end

  defp decode_points(_rest, _count, _precise, acc), do: Enum.reverse(acc)

  defp command_to_svg(%{kind: :circle} = command, scale) do
    [%{x: cx, y: cy}] = command.points
    r = command.radius || 0
    fill = pebble_color_to_css(command.fill_color)
    stroke = pebble_color_to_css(command.stroke_color)
    stroke_width = max(command.stroke_width, if(stroke, do: 1, else: 0))

    attrs =
      [
        ~s(cx="#{scale_coord(cx, scale)}"),
        ~s(cy="#{scale_coord(cy, scale)}"),
        ~s(r="#{scale_coord(r, scale)}"),
        fill_attr(fill),
        stroke_attr(stroke),
        if(stroke_width > 0, do: ~s(stroke-width="#{stroke_width}"), else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    "<circle #{attrs} />"
  end

  defp command_to_svg(%{kind: :path} = command, scale) do
    points = command.points

    if points == [] do
      ""
    else
      d = path_d(points, scale, command.open)
      fill = pebble_color_to_css(command.fill_color)
      stroke = pebble_color_to_css(command.stroke_color)
      stroke_width = max(command.stroke_width, if(stroke && command.open, do: 1, else: 0))

      attrs =
        [
          ~s(d="#{d}"),
          fill_attr(if(command.open, do: "none", else: fill)),
          stroke_attr(stroke),
          if(stroke_width > 0, do: ~s(stroke-width="#{stroke_width}"), else: nil)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")

      "<path #{attrs} />"
    end
  end

  defp command_to_debugger_ops(%{kind: :path} = command, offset_x, offset_y) do
    points =
      Enum.map(command.points, fn %{x: x, y: y} ->
        %{"x" => x + offset_x, "y" => y + offset_y}
      end)

    base = %{
      points: points,
      offset_x: 0,
      offset_y: 0,
      rotation: 0,
      stroke_color: command.stroke_color,
      stroke_width: max(command.stroke_width, 1)
    }

    cond do
      command.open ->
        [Map.merge(base, %{kind: :path_outline_open, fill_color: 0})]

      command.fill_color != 0 ->
        [Map.merge(base, %{kind: :path_filled, fill_color: command.fill_color})]

      command.stroke_color != 0 ->
        [Map.merge(base, %{kind: :path_outline, fill_color: 0})]

      true ->
        []
    end
  end

  defp command_to_debugger_ops(%{kind: :circle} = command, offset_x, offset_y) do
    [%{x: cx, y: cy}] = command.points
    cx = cx + offset_x
    cy = cy + offset_y
    r = command.radius || 0

    cond do
      command.fill_color != 0 ->
        [
          %{
            kind: :fill_circle,
            cx: cx,
            cy: cy,
            r: r,
            fill_color: command.fill_color,
            stroke_color: command.stroke_color,
            stroke_width: max(command.stroke_width, 1)
          }
        ]

      command.stroke_color != 0 ->
        [
          %{
            kind: :circle,
            cx: cx,
            cy: cy,
            r: r,
            color: command.stroke_color,
            stroke_color: command.stroke_color,
            stroke_width: max(command.stroke_width, 1)
          }
        ]

      true ->
        []
    end
  end

  defp path_d([first | rest], scale, open?) do
    move = "M #{scale_coord(first.x, scale)} #{scale_coord(first.y, scale)}"

    segments =
      rest
      |> Enum.map(fn %{x: x, y: y} ->
        "L #{scale_coord(x, scale)} #{scale_coord(y, scale)}"
      end)
      |> Enum.join(" ")

    close = if open?, do: "", else: " Z"
    move <> " " <> segments <> close
  end

  defp scale_coord(value, scale) when is_number(value) and is_number(scale),
    do: Float.round(value * scale, 2)

  defp fill_attr(nil), do: ~s(fill="none")
  defp fill_attr(color), do: ~s(fill="#{color}")

  defp stroke_attr(nil), do: nil
  defp stroke_attr(color), do: ~s(stroke="#{color}")

  defp pebble_color_to_css(0), do: nil

  defp pebble_color_to_css(value) when is_integer(value) do
    alpha = value |> Bitwise.bsr(6) |> Bitwise.band(0x03)
    red = value |> Bitwise.bsr(4) |> Bitwise.band(0x03)
    green = value |> Bitwise.bsr(2) |> Bitwise.band(0x03)
    blue = Bitwise.band(value, 0x03)

    if alpha == 0 do
      nil
    else
      [red, green, blue]
      |> Enum.map(&channel_to_hex/1)
      |> Enum.join()
      |> then(&"##{&1}")
    end
  end

  defp channel_to_hex(value) do
    value
    |> max(0)
    |> min(3)
    |> Kernel.*(85)
    |> Integer.to_string(16)
    |> String.pad_leading(2, "0")
  end

  @spec validate_watch_compatible(binary()) :: :ok | {:error, watch_validate_error()}
  def validate_watch_compatible(bytes) when is_binary(bytes) do
    with {:ok, summary} <- watch_summary(bytes),
         :ok <- validate_watch_summary(summary, bytes) do
      :ok
    end
  end

  def validate_watch_compatible(_), do: {:error, :invalid_pdc}

  defp watch_summary(bytes) do
    case decode_sequence(bytes) do
      {:ok, %{width: width, height: height, frames: frames}} ->
        {:ok,
         %{
           width: abs(width),
           height: abs(height),
           frame_count: length(frames)
         }}

      {:error, _} ->
        case decode(bytes) do
          {:ok, %{width: width, height: height}} ->
            {:ok, %{width: abs(width), height: abs(height), frame_count: 1}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp validate_watch_summary(summary, bytes) do
    cond do
      byte_size(bytes) > @max_watch_bytes ->
        {:error, :pdc_too_large}

      summary.width > @max_watch_dimension or summary.height > @max_watch_dimension ->
        {:error, :pdc_dimensions_too_large}

      summary.frame_count > @max_watch_frames ->
        {:error, :pdc_too_many_frames}

      summary.width < 1 or summary.height < 1 ->
        {:error, :invalid_watch_pdc}

      true ->
        :ok
    end
  end
end
