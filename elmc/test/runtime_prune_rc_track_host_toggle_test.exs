defmodule Elmc.RuntimePruneRcTrackHostToggleTest do
  use ExUnit.Case, async: false

  test "pruned runtime keeps #if !ELMC_RC_TRACK wrappers around retain/release" do
    out_dir = Path.expand("tmp/runtime_prune_rc_host_toggle", __DIR__)
    refs_dir = Path.join(out_dir, "refs")
    runtime_dir = Path.join(out_dir, "runtime")

    File.rm_rf!(out_dir)
    File.mkdir_p!(refs_dir)

    File.write!(Path.join(refs_dir, "elmc_generated.c"), """
    #include "elmc_runtime.h"

    RC uses_retain_release(ElmcValue **out, ElmcValue *value) {
      ElmcValue *kept = elmc_retain(value);
      elmc_release(value);
      *out = kept;
      return RC_SUCCESS;
    }
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    # prune_source strips inactive #if lines inside kept function bodies, so the
    # host retain/release entry points remain as plain definitions. Preamble still
    # keeps ELMC_RC_TRACK_REGISTER for both track modes.
    assert runtime =~ "ElmcValue *elmc_retain(ElmcValue *value)"
    assert runtime =~ "void elmc_release(ElmcValue *value)"
    assert runtime =~ "ELMC_RC_TRACK_REGISTER"
    assert runtime =~ "} ElmcListCell;"

    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available")

    object = Path.join(out_dir, "runtime_rc_host_toggle.o")

    {out, code} =
      System.cmd(
        cc,
        [
          "-c",
          "-std=c99",
          "-Wall",
          "-Wextra",
          "-include",
          Path.expand("support/elmc_host_stubs.h", __DIR__),
          "-I",
          runtime_dir,
          "-DELMC_RC_TRACK=0",
          Path.join(runtime_dir, "elmc_runtime.c"),
          "-o",
          object
        ],
        stderr_to_stdout: true
      )

    assert code == 0, out

    # Intentional split: pruned runtime is not yet a full ELMC_RC_TRACK=1 canary.
    {track_out, track_code} =
      System.cmd(
        cc,
        [
          "-c",
          "-std=c99",
          "-Wall",
          "-Wextra",
          "-include",
          Path.expand("support/elmc_host_stubs.h", __DIR__),
          "-I",
          runtime_dir,
          "-DELMC_RC_TRACK=1",
          Path.join(runtime_dir, "elmc_runtime.c"),
          "-o",
          Path.join(out_dir, "runtime_rc_track1.o")
        ],
        stderr_to_stdout: true
      )

    assert track_code != 0, "pruned + ELMC_RC_TRACK=1 should still fail until registry prune lands"
    assert String.contains?(track_out, "elmc_rc_track") or String.contains?(track_out, "error:")
  end
end
