defmodule Ide.Resources.PdcEncoder do
  @moduledoc """
  Encodes Pebble Draw Command images and sequences into PDCI/PDCS binaries.

  Uses the same command shape as `Ide.Resources.PdcDecoder`.
  """

  alias Ide.Resources.PdcDecoder

  @command_type_path 1
  @command_type_circle 2
  @command_type_precise_path 3

  @type encode_error :: :invalid_image

  @spec encode(PdcDecoder.image()) :: {:ok, binary()} | {:error, encode_error()}
  def encode(%{width: width, height: height, commands: commands})
      when is_integer(width) and is_integer(height) and is_list(commands) do
    payload = pack_header(width, height) <> serialize_commands(commands)
    {:ok, "PDCI" <> <<byte_size(payload)::32-little>> <> payload}
  end

  def encode(_), do: {:error, :invalid_image}

  @spec encode_sequence([PdcDecoder.image()], keyword()) :: {:ok, binary()} | {:error, encode_error()}
  def encode_sequence(frames, opts \\ [])

  def encode_sequence([], _opts), do: {:error, :invalid_image}

  def encode_sequence(frames, opts) when is_list(frames) and frames != [] do
    frame_duration_ms = Keyword.get(opts, :frame_duration_ms, 100)
    play_count = Keyword.get(opts, :play_count, 1)

    [%{width: width, height: height} | _] = frames

    payload =
      pack_header(width, height) <>
        <<play_count::16-little, length(frames)::16-little>> <>
        Enum.map_join(frames, &serialize_frame(&1, frame_duration_ms))

    {:ok, "PDCS" <> <<byte_size(payload)::32-little>> <> payload}
  end

  defp pack_header(width, height) do
    <<1, 0, width::16-little-signed, height::16-little-signed>>
  end

  defp serialize_frame(%{commands: commands}, duration_ms) do
    <<duration_ms::16-little>> <> serialize_commands(commands)
  end

  defp serialize_commands(commands) do
    <<length(commands)::16-little>> <> Enum.map_join(commands, &serialize_command/1)
  end

  defp serialize_command(%{kind: :path} = command) do
    type = if command.precise, do: @command_type_precise_path, else: @command_type_path
    open = if command.open, do: 1, else: 0
    points = command.points || []

    <<
      type,
      0,
      command.stroke_color,
      command.stroke_width,
      command.fill_color,
      open,
      0,
      length(points)::16-little
    >> <> serialize_points(points, command.precise)
  end

  defp serialize_command(%{kind: :circle} = command) do
    [%{x: cx, y: cy}] = command.points
    radius = command.radius || 0

    <<
      @command_type_circle,
      0,
      command.stroke_color,
      command.stroke_width,
      command.fill_color,
      radius::16-little,
      1::16-little,
      cx::16-little-signed,
      cy::16-little-signed
    >>
  end

  defp serialize_points(points, precise?) do
    Enum.map(points, fn %{x: x, y: y} ->
      {x, y} = if precise?, do: {x * 8, y * 8}, else: {x, y}
      <<x::16-little-signed, y::16-little-signed>>
    end)
    |> IO.iodata_to_binary()
  end
end
