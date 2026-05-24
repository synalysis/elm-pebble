defmodule Ide.Resources.PdcDecoderTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.PdcDecoder

  @tangram_bird Path.expand(
                  "../../../priv/project_templates/watchface_tangram_time/resources/vectors/TangramBird.pdc",
                  __DIR__
                )

  @weather_transition Path.expand(
                        "../../../priv/project_templates/watchface_weather_animated/resources/vectors/TransitionClearToRain.pdc",
                        __DIR__
                      )

  test "decode TangramBird.pdc and render preview svg" do
    bytes = File.read!(@tangram_bird)

    assert {:ok, image} = PdcDecoder.decode(bytes)
    assert image.width == 132
    assert image.height == 126
    assert length(image.commands) == 7

    assert {:ok, svg} = PdcDecoder.preview_svg(bytes)
    assert svg =~ "<svg"
    assert svg =~ "<path"
  end

  test "to_debugger_ops offsets paths and circles" do
    bytes = File.read!(@tangram_bird)
    {:ok, image} = PdcDecoder.decode(bytes)

    ops = PdcDecoder.to_debugger_ops(image, 12, 34)
    assert Enum.any?(ops, &(&1.kind == :path_filled))

    [%{points: [%{"x" => x, "y" => y} | _]} | _] =
      Enum.filter(ops, &(&1.kind == :path_filled))

    assert x >= 12
    assert y >= 34
  end

  test "decode_sequence_frame returns requested frame from PDCS payload" do
    image = %{
      width: 12,
      height: 10,
      commands: [
        %{
          kind: :path,
          open: false,
          stroke_color: 0,
          stroke_width: 0,
          fill_color: 85,
          points: [%{x: 1, y: 2}, %{x: 3, y: 4}],
          radius: nil,
          precise: false
        }
      ]
    }

    other = %{image | commands: [Map.put(hd(image.commands), :fill_color, 170)]}

    assert {:ok, pdci_a} = Ide.Resources.PdcEncoder.encode(image)
    assert {:ok, pdci_b} = Ide.Resources.PdcEncoder.encode(other)

    command_list_a = pdci_command_list(pdci_a)
    command_list_b = pdci_command_list(pdci_b)

    sequence_payload =
      <<1, 0, 12::16-little-signed, 10::16-little-signed, 1::16-little, 2::16-little,
        50::16-little, command_list_a::binary, 75::16-little, command_list_b::binary>>

    pdcs = "PDCS" <> <<byte_size(sequence_payload)::32-little>> <> sequence_payload

    assert {:ok, frame0} = PdcDecoder.decode_sequence_frame(pdcs, 0)
    assert frame0.width == 12
    assert hd(frame0.commands).fill_color == 85

    assert {:ok, frame1} = PdcDecoder.decode_sequence_frame(pdcs, 1)
    assert hd(frame1.commands).fill_color == 170
  end

  test "decode_sequence returns all frames with durations" do
    image = %{
      width: 12,
      height: 10,
      commands: [
        %{
          kind: :path,
          open: false,
          stroke_color: 0,
          stroke_width: 0,
          fill_color: 85,
          points: [%{x: 1, y: 2}, %{x: 3, y: 4}],
          radius: nil,
          precise: false
        }
      ]
    }

    other = %{image | commands: [Map.put(hd(image.commands), :fill_color, 170)]}

    assert {:ok, pdci_a} = Ide.Resources.PdcEncoder.encode(image)
    assert {:ok, pdci_b} = Ide.Resources.PdcEncoder.encode(other)

    sequence_payload =
      <<1, 0, 12::16-little-signed, 10::16-little-signed, 1::16-little, 2::16-little,
        50::16-little, pdci_command_list(pdci_a)::binary, 75::16-little,
        pdci_command_list(pdci_b)::binary>>

    pdcs = "PDCS" <> <<byte_size(sequence_payload)::32-little>> <> sequence_payload

    assert {:ok, sequence} = PdcDecoder.decode_sequence(pdcs)
    assert sequence.width == 12
    assert sequence.height == 10
    assert sequence.play_count == 1
    assert length(sequence.frames) == 2
    assert Enum.at(sequence.frames, 0).duration_ms == 50
    assert Enum.at(sequence.frames, 1).duration_ms == 75
    assert hd(Enum.at(sequence.frames, 0).image.commands).fill_color == 85
    assert hd(Enum.at(sequence.frames, 1).image.commands).fill_color == 170
  end

  test "to_svg_elements renders path markup without wrapper svg" do
    bytes = File.read!(@tangram_bird)
    {:ok, image} = PdcDecoder.decode(bytes)
    elements = PdcDecoder.to_svg_elements(image)
    refute elements =~ "<svg"
    assert elements =~ "<path"
  end

  test "decode_sequence decodes weather transition assets with multiple frames" do
    bytes = File.read!(@weather_transition)

    assert {:ok, sequence} = PdcDecoder.decode_sequence(bytes)
    assert length(sequence.frames) >= 2
    assert Enum.all?(sequence.frames, &(&1.duration_ms > 0))

    elements = PdcDecoder.to_svg_elements(hd(sequence.frames).image)
    assert elements =~ "<path" or elements =~ "<circle"
  end

  defp pdci_command_list(<<"PDCI", _size::32-little, 1, 0, _w::16, _h::16, rest::binary>>),
    do: rest

  defp pdci_command_list(_), do: <<>>
end
