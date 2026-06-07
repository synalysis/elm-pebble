defmodule Ide.Emulator.WatchFaultTest do
  use ExUnit.Case, async: true

  @watch_fault_js Path.expand("../../../assets/js/emulator/watch_fault.ts", __DIR__)

  test "watch_fault.ts classifies ELMC allocation failures" do
    source = File.read!(@watch_fault_js)
    assert source =~ "ELMC allocation failed"
    assert source =~ "insufficient memory"
    assert source =~ "App fault!"
    assert source =~ "Watch app ran out of memory"
    assert source =~ "Watch app crashed"
  end

  test "embedded emulator page includes watch fault banner" do
    page = File.read!(Path.expand("../../../lib/ide_web/live/workspace_live/emulator_page.ex", __DIR__))
    assert page =~ "data-emulator-fault-banner"
    assert page =~ "data-emulator-fault-headline"
    assert page =~ "role=\"alert\""
  end
end
