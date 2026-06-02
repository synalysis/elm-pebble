defmodule Ide.Resources.ApngProbeTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.{ApngProbe, GifToApng}

  @gif_fixture Path.expand("../../fixtures/animations/simple.gif", __DIR__)

  test "probe accepts APNG8 produced from gif2apng" do
    case GifToApng.gif2apng_bin() do
      nil ->
        :ok

      _bin ->
        tmp = System.tmp_dir!()
        gif = Path.join(tmp, "apng8_in_#{System.unique_integer([:positive])}.gif")
        png = Path.join(tmp, "apng8_out_#{System.unique_integer([:positive])}.png")
        File.cp!(@gif_fixture, gif)
        assert :ok = GifToApng.convert(gif, png)
        assert {:ok, %{frame_count: frames}} = ApngProbe.probe(png)
        assert frames > 1
    end
  end

  test "probe rejects RGBA APNG (not APNG8)" do
    bytes = rgba_apng_fixture()

    assert {:error, :requires_apng8} = ApngProbe.probe_bytes(bytes)
  end

  test "probe rejects APNG with acTL but missing fcTL frames" do
    bytes = malformed_apng_fixture()

    assert {:error, :malformed_apng} = ApngProbe.probe_bytes(bytes)
  end

  defp rgba_apng_fixture do
    # Minimal valid PNG signature + IHDR (8-bit RGBA) + acTL claiming 2 frames + IEND
    ihdr =
      <<0, 0, 0, 16, 0, 0, 0, 16, 8, 6, 0, 0, 0>>
      |> then(fn data -> png_chunk("IHDR", data) end)

    actl = png_chunk("acTL", <<2::32, 0::32>>)
    iend = png_chunk("IEND", <<>>)

    <<137, 80, 78, 71, 13, 10, 26, 10, ihdr::binary, actl::binary, iend::binary>>
  end

  defp malformed_apng_fixture do
    ihdr =
      <<0, 0, 0, 16, 0, 0, 0, 16, 8, 3, 0, 0, 0>>
      |> then(fn data -> png_chunk("IHDR", data) end)

    actl = png_chunk("acTL", <<4::32, 0::32>>)
    fctl = png_chunk("fcTL", <<0::32, 16::32, 16::32, 0::32, 0::32, 10::16, 100::16, 0>>)
    iend = png_chunk("IEND", <<>>)

    <<137, 80, 78, 71, 13, 10, 26, 10, ihdr::binary, actl::binary, fctl::binary, iend::binary>>
  end

  defp png_chunk(type, data) do
    crc = :erlang.crc32(type <> data)
    <<byte_size(data)::32, type::binary, data::binary, crc::32>>
  end
end
