defmodule Ide.Resources.SvgConverterTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.{PdcDecoder, SvgConverter}

  test "validate_pdc_bytes accepts PDCI header" do
    assert :ok =
             SvgConverter.validate_pdc_bytes(
               <<0x50, 0x44, 0x43, 0x49, 0x1D, 0x00, 0x00, 0x00, 0x01>>
             )
  end

  test "convert_svg_to_pdc produces a PDC file" do
    svg_path =
      Path.join(System.tmp_dir!(), "svg_converter_#{System.unique_integer([:positive])}.svg")

    pdc_path =
      Path.join(System.tmp_dir!(), "svg_converter_#{System.unique_integer([:positive])}.pdc")

    File.write!(
      svg_path,
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><polygon points="2,18 10,2 18,18" fill="#000000"/></svg>)
    )

    on_exit(fn ->
      File.rm(svg_path)
      File.rm(pdc_path)
    end)

    assert :ok = SvgConverter.convert_svg_to_pdc(svg_path, pdc_path)
    assert {:ok, bytes} = File.read(pdc_path)
    assert SvgConverter.pdc_magic(bytes) == "PDCI"
    assert {:ok, image} = PdcDecoder.decode(bytes)
    assert length(image.commands) == 1
  end

  test "convert_svg_string supports Pebble named fill colors" do
    svg = ~s(
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
        <polygon points="2,18 10,2 18,18" fill="vividCerulean"/>
      </svg>
    )

    assert {:ok, %SvgConverter.ConversionResult{bytes: bytes}} =
             SvgConverter.convert_svg_string(svg)

    assert {:ok, image} = PdcDecoder.decode(bytes)
    [%{fill_color: fill_color}] = image.commands
    assert fill_color == 0xCB
  end

  test "convert_svg_string supports css black keyword" do
    svg = ~s(
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
        <rect x="1" y="1" width="8" height="8" fill="black"/>
      </svg>
    )

    assert {:ok, %SvgConverter.ConversionResult{bytes: bytes}} =
             SvgConverter.convert_svg_string(svg)

    assert {:ok, image} = PdcDecoder.decode(bytes)
    [%{fill_color: fill_color}] = image.commands
    assert fill_color == 0xC0
  end

  test "convert_svg_string produces multiple filled paths for tangram-style svg" do
    svg = ~s(
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 132 126">
        <polygon points="58,52 16,22 6,62" fill="#0055FF"/>
        <polygon points="74,52 108,22 118,62" fill="#00AAFF"/>
        <polygon points="48,60 66,46 84,60 66,76" fill="#55FFFF"/>
        <polygon points="84,54 102,46 98,66" fill="#00FFFF"/>
        <polygon points="48,66 26,58 20,74 42,82" fill="#001133"/>
        <polygon points="61,76 38,92 70,90" fill="#0055DD"/>
        <polygon points="72,76 100,90 78,94" fill="#AADDFF"/>
      </svg>
    )

    assert {:ok, %SvgConverter.ConversionResult{bytes: bytes}} =
             SvgConverter.convert_svg_string(svg)

    assert {:ok, converted} = PdcDecoder.decode(bytes)
    assert converted.width == 132
    assert converted.height == 126
    assert length(converted.commands) == 7
    assert Enum.all?(converted.commands, &(&1.kind == :path and &1.fill_color != 0))
  end

  test "convert skips display none elements" do
    svg = ~s(
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
        <rect x="1" y="1" width="8" height="8" fill="black" display="none"/>
        <rect x="2" y="2" width="6" height="6" fill="black"/>
      </svg>
    )

    assert {:ok, %SvgConverter.ConversionResult{bytes: bytes, report: report}} =
             SvgConverter.convert_svg_string(svg)

    assert {:ok, image} = PdcDecoder.decode(bytes)
    assert length(image.commands) == 1
    assert report.stats.commands == 1
  end

  test "convert_svg_sequence produces PDCS bytes" do
    frames = [
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect x="1" y="1" width="4" height="4" fill="black"/></svg>),
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect x="5" y="5" width="4" height="4" fill="black"/></svg>)
    ]

    assert {:ok, %SvgConverter.ConversionResult{bytes: bytes}} =
             SvgConverter.convert_svg_sequence(frames, frame_duration_ms: 50)

    assert SvgConverter.pdc_magic(bytes) == "PDCS"
  end

  test "nearest color mode can differ from truncate for mid-range channel values" do
    svg =
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect x="1" y="1" width="4" height="4" fill="#424242"/></svg>)

    assert {:ok, %{bytes: truncate_bytes}} = SvgConverter.convert(svg, color_mode: :truncate)
    assert {:ok, %{bytes: nearest_bytes}} = SvgConverter.convert(svg, color_mode: :nearest)

    assert {:ok, truncate_image} = PdcDecoder.decode(truncate_bytes)
    assert {:ok, nearest_image} = PdcDecoder.decode(nearest_bytes)
    refute hd(truncate_image.commands).fill_color == hd(nearest_image.commands).fill_color
  end
end
