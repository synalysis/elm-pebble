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
end
