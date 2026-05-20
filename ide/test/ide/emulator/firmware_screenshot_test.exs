defmodule Ide.Emulator.FirmwareScreenshotTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.FirmwareScreenshot

  test "parse_header_payload reads big-endian screenshot header" do
    payload =
      <<0, 1::unsigned-big-32, 144::unsigned-big-32, 168::unsigned-big-32, 0xAA, 0xBB>>

    assert {:ok, header, <<0xAA, 0xBB>>} = FirmwareScreenshot.parse_header_payload(payload)
    assert header.version == 1
    assert header.width == 144
    assert header.height == 168
    assert header.expected_bytes == div(144 * 168, 8)
  end

  test "parse_header_payload accepts version 2 8bpp screenshots" do
    payload = <<0, 2::unsigned-big-32, 180::unsigned-big-32, 180::unsigned-big-32, 1, 2, 3>>

    assert {:ok, header, <<1, 2, 3>>} = FirmwareScreenshot.parse_header_payload(payload)
    assert header.version == 2
    assert header.expected_bytes == 180 * 180
  end

  test "decode_8bpp produces rgb triplets" do
    data = <<0xFF, 0x00, 0xAA, 0x55>>
    rgb = FirmwareScreenshot.decode_8bpp(2, 2, data)
    assert byte_size(rgb) == 12
    assert :binary.part(rgb, 0, 3) == <<255, 255, 255>>
  end

  test "capture_timeout_ms scales for large color watch screenshots" do
    assert FirmwareScreenshot.capture_timeout_ms("gabbro") >= 55_000
    assert FirmwareScreenshot.capture_timeout_ms("chalk") >= 25_000
    assert FirmwareScreenshot.capture_timeout_ms("basalt") >= 25_000
    assert FirmwareScreenshot.capture_timeout_ms("gabbro") <= 90_000
  end
end
