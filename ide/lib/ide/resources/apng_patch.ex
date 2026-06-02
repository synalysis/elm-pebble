defmodule Ide.Resources.ApngPatch do
  @moduledoc """
  Patches APNG resources for Pebble firmware expectations.

  APNG `num_plays == 0` means infinite loop, but Pebble's `GBitmapSequence` treats
  `play_count == 0` as "updates disabled". Pebble infinite looping uses
  `PLAY_COUNT_INFINITE` (`0xFFFFFFFF`), which matches APNG `num_plays` when set to
  that value in the `acTL` chunk.
  """

  @pebble_infinite_plays 0xFFFFFFFF

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @spec pebble_stage_bytes(binary()) :: binary()
  def pebble_stage_bytes(bytes) when is_binary(bytes) do
    patch_actl_infinite_plays(bytes, @pebble_infinite_plays)
  end

  @spec patch_actl_infinite_plays(binary(), non_neg_integer()) :: binary()
  def patch_actl_infinite_plays(bytes, plays \\ @pebble_infinite_plays)
      when is_binary(bytes) and is_integer(plays) and plays >= 0 do
    case bytes do
      @png_signature <> rest ->
        patch_chunks(rest, @png_signature, plays)

      _ ->
        bytes
    end
  end

  defp patch_chunks(<<>>, acc, _plays), do: acc

  defp patch_chunks(
         <<length::32-big, type::4-binary, data::binary-size(length), crc::32-big, rest::binary>>,
         acc,
         plays
       ) do
    {data, crc} =
      if type == "acTL" and byte_size(data) >= 8 do
        <<num_frames::32-big, num_plays::32-big, tail::binary>> = data

        if num_plays == 0 do
          patched = <<num_frames::32-big, plays::32-big, tail::binary>>
          {patched, :erlang.crc32(<<"acTL", patched::binary>>)}
        else
          {data, crc}
        end
      else
        {data, crc}
      end

    patch_chunks(rest, acc <> <<length::32-big, type::4-binary, data::binary, crc::32-big>>, plays)
  end

  defp patch_chunks(rest, acc, _plays) when is_binary(rest) do
    acc <> rest
  end
end
