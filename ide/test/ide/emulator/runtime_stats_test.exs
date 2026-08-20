defmodule Ide.Emulator.RuntimeStatsTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.RuntimeStats

  test "parse/1 reads the elmc-stats contract from a raw line" do
    assert RuntimeStats.parse(
             "elmc-stats scene_bytes=256 scene_cmds=12 scene_cap=768 heap_free=5000 heap_free_min=4800"
           ) == %{
             scene_bytes: 256,
             scene_cmds: 12,
             scene_cap: 768,
             heap_free: 5000,
             heap_free_min: 4800
           }
  end

  test "parse/1 reads the contract from an AppLog wrapper" do
    line =
      "AppLog INFO elmc_pebble.c:42: elmc-stats scene_bytes=320 scene_cmds=18 scene_cap=768 heap_free=1600 heap_free_min=1500"

    assert RuntimeStats.parse(line) == %{
             scene_bytes: 320,
             scene_cmds: 18,
             scene_cap: 768,
             heap_free: 1600,
             heap_free_min: 1500
           }
  end

  test "parse/1 ignores incomplete or unrelated lines" do
    assert RuntimeStats.parse("elmc-stats scene_bytes=1") == nil
    assert RuntimeStats.parse("AppLog INFO elmc_pebble.c:1: scene encode ok") == nil
  end

  test "merge/2 keeps watermarks and the latest heap_free" do
    first = %{
      scene_bytes: 200,
      scene_cmds: 10,
      scene_cap: 512,
      heap_free: 4000,
      heap_free_min: 3900
    }

    second = %{
      scene_bytes: 256,
      scene_cmds: 8,
      scene_cap: 768,
      heap_free: 3500,
      heap_free_min: 4100
    }

    assert RuntimeStats.merge(first, second) == %{
             scene_bytes: 256,
             scene_cmds: 10,
             scene_cap: 768,
             heap_free: 3500,
             heap_free_min: 3900
           }
  end

  test "parse_many/1 merges several contract lines" do
    lines = [
      "noise",
      "elmc-stats scene_bytes=100 scene_cmds=4 scene_cap=768 heap_free=2000 heap_free_min=2000",
      "elmc-stats scene_bytes=140 scene_cmds=9 scene_cap=768 heap_free=1800 heap_free_min=1700"
    ]

    assert RuntimeStats.parse_many(lines) == %{
             scene_bytes: 140,
             scene_cmds: 9,
             scene_cap: 768,
             heap_free: 1800,
             heap_free_min: 1700
           }
  end
end
