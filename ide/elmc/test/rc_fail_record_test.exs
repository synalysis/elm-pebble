defmodule Elmc.RcFailRecordTest do
  use ExUnit.Case, async: true

  alias Elmc.Runtime.{Generator, RcMacros}

  test "RC macros define allocation-free last-fail stash" do
    header = RcMacros.header_declarations()
    source = RcMacros.source_impl()

    assert header =~ "extern volatile RC elmc_last_fail_rc"
    assert header =~ "extern volatile uint16_t elmc_last_fail_line"
    assert header =~ "static inline void elmc_rc_record_fail(RC rc, int line)"
    assert header =~ "elmc_rc_record_fail((rc_var), __LINE__)"
    assert source =~ "volatile RC elmc_last_fail_rc = RC_SUCCESS"
    assert source =~ "volatile uint16_t elmc_last_fail_line = 0"
  end

  test "pebble device ELMC_RC_LOG_FAIL records numeric rc without elmc_rc_name" do
    header = RcMacros.header_declarations()

    assert header =~ ~s/APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC RC %u at %s", (unsigned)(rc), site)/

    pebble_branch =
      header
      |> String.split("#ifdef ELMC_PEBBLE_PLATFORM")
      |> Enum.at(1, "")
      |> String.split("#else")
      |> hd()

    refute pebble_branch =~ "elmc_rc_name(rc)"
  end

  test "runtime generator retains last-fail globals" do
    tmp = Path.expand("tmp/rc_fail_record_runtime", __DIR__)
    File.rm_rf!(tmp)
    assert :ok = Generator.write_runtime(tmp, pebble_int32: true)

    header = File.read!(Path.join(tmp, "elmc_runtime.h"))
    source = File.read!(Path.join(tmp, "elmc_runtime.c"))

    assert header =~ "elmc_last_fail_rc"
    assert source =~ "volatile RC elmc_last_fail_rc"
  end

  test "pruned pebble runtime keeps elmc_rc_name behind ELMC_PEBBLE_PLATFORM guard" do
    tmp = Path.expand("tmp/rc_fail_record_pruned", __DIR__)
    refs_dir = Path.expand("tmp/rc_fail_record_pruned_refs", __DIR__)
    File.rm_rf!(tmp)
    File.rm_rf!(refs_dir)
    File.mkdir_p!(Path.join(refs_dir, "c"))

    File.write!(
      Path.join(refs_dir, "c/elmc_pebble.c"),
      """
      void elmc_rc_name_probe(void) {
        (void)elmc_rc_name(RC_SUCCESS);
      }
      """
    )

    assert :ok = Generator.write_runtime(tmp, prune_from_dir: refs_dir, pebble_int32: true)

    source = File.read!(Path.join(tmp, "elmc_runtime.c"))

    assert {guard_idx, _} = :binary.match(source, "#ifndef ELMC_PEBBLE_PLATFORM")
    assert {name_idx, _} = :binary.match(source, "const char *elmc_rc_name(RC rc)")
    assert guard_idx < name_idx
    assert Regex.scan(~r/const char \*elmc_rc_name\(RC rc\) \{/, source) |> length() == 1
  end

  test "pruned pebble runtime drops host-only alloc track helpers" do
    tmp = Path.expand("tmp/rc_fail_record_alloc_track_pruned", __DIR__)
    refs_dir = Path.expand("tmp/rc_fail_record_alloc_track_pruned_refs", __DIR__)
    File.rm_rf!(tmp)
    File.rm_rf!(refs_dir)
    File.mkdir_p!(Path.join(refs_dir, "c"))

    File.write!(
      Path.join(refs_dir, "c/elmc_generated.c"),
      """
      #include "elmc_runtime.h"
      void elmc_alloc_probe(void) {
        ElmcValue *v = elmc_new_int_take(1);
        elmc_release(v);
      }
      """
    )

    assert :ok = Generator.write_runtime(tmp, prune_from_dir: refs_dir, pebble_int32: true)

    source = File.read!(Path.join(tmp, "elmc_runtime.c"))

    refute source =~ "static void elmc_alloc_track_register("
    refute source =~ "ELMC_ALLOC_TRACK_ENTRIES"
    refute source =~ "static ElmcValue ELMC_UNIT ="
  end
end
