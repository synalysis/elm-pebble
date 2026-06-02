defmodule Ide.Resources.ApngPatchTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.ApngPatch

  test "pebble_stage_bytes rewrites acTL num_plays 0 to infinite" do
    bytes = minimal_apng_bytes(plays: 0)
    patched = ApngPatch.pebble_stage_bytes(bytes)

    assert patched != bytes
    assert <<_::32-big, 0xFFFFFFFF::32-big>> = actl_payload(patched)
  end

  test "pebble_stage_bytes leaves finite play counts unchanged" do
    bytes = minimal_apng_bytes(plays: 2)
    patched = ApngPatch.pebble_stage_bytes(bytes)

    assert patched == bytes
    assert <<_::32-big, 2::32-big>> = actl_payload(patched)
  end

  defp actl_payload(bytes) do
    <<_::binary-size(8), rest::binary>> = bytes
    actl_payload_from_chunks(rest)
  end

  defp actl_payload_from_chunks(<<length::32, "acTL", payload::binary-size(length), _crc::32, _rest::binary>>) do
    payload
  end

  defp actl_payload_from_chunks(<<length::32, _type::binary-size(4), _data::binary-size(length), _crc::32, rest::binary>>) do
    actl_payload_from_chunks(rest)
  end

  defp minimal_apng_bytes(opts) do
    plays = Keyword.get(opts, :plays, 0)
    signature = <<137, 80, 78, 71, 13, 10, 26, 10>>
    ihdr = png_chunk("IHDR", <<1::32, 1::32, 8, 3, 0, 0, 0>>)
    actl = png_chunk("acTL", <<1::32, plays::32>>)
    idat = png_chunk("IDAT", <<>>)
    iend = png_chunk("IEND", <<>>)
    signature <> ihdr <> actl <> idat <> iend
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32(type <> data)
    <<byte_size(data)::32, type::binary, data::binary, crc::32>>
  end
end
