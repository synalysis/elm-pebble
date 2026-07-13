defmodule Elmc.RuntimePruneSpeakerTest do
  use ExUnit.Case, async: false

  test "speaker play-tracks pebble glue keeps maybe just payload borrow helper" do
    out_dir = Path.expand("tmp/runtime_prune_speaker_out", __DIR__)
    refs_dir = Path.join(out_dir, "refs")
    runtime_dir = Path.join(out_dir, "runtime")
    c_dir = Path.join(refs_dir, "c")

    File.rm_rf!(out_dir)
    File.mkdir_p!(c_dir)

    File.write!(Path.join(c_dir, "elmc_pebble.h"), """
    #define ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_NOTES 0
    #define ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_TRACKS 1
    """)

    File.write!(Path.join(c_dir, "elmc_pebble.c"), """
    #include "elmc_pebble.h"
    #include "elmc_runtime.h"

    #if ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_NOTES || ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_TRACKS
    static int32_t elmc_speaker_sample_index_from_maybe(ElmcValue *maybe_sample) {
      ElmcValue *sample = elmc_maybe_or_tuple_just_payload_borrow(maybe_sample);
      if (!sample) return 0;
      return (int32_t)elmc_as_int(sample);
    }

    static int elmc_serialize_speaker_tracks(
        ElmcValue *value,
        char *out_text,
        size_t out_size,
        int32_t *out_count) {
      (void)value;
      (void)out_text;
      (void)out_size;
      (void)out_count;
      return 0;
    }
    #endif
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))
    header = File.read!(Path.join(runtime_dir, "elmc_runtime.h"))

    assert runtime =~ "elmc_maybe_or_tuple_just_payload_borrow(ElmcValue *maybe)"
    assert header =~ "elmc_maybe_or_tuple_just_payload_borrow(ElmcValue *maybe)"
  end
end
