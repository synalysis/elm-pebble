defmodule Elmc.LinkedBinaryReportTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.{LinkedBinaryReport, StackEstimate, StackReport}

  @sample_map """
  .text           0x00000000      0x100
   0x00000000      0x00000400      elmc_fn_Main_update
   0x00000400      0x00000200      elmc_release_impl
   0x00000600      0x00000080      app_main
  """

  test "from_map extracts top and elmc symbols" do
    linked = LinkedBinaryReport.from_map(@sample_map, map_path: "build/basalt/pebble-app.map")

    assert linked["available"]
    assert linked["map_path"] == "build/basalt/pebble-app.map"
    assert linked["elmc_text_bytes"] == 0x400 + 0x200
    assert Enum.any?(linked["top_symbols"], &(&1["symbol"] == "elmc_fn_Main_update"))
    assert Enum.any?(linked["elmc_symbols"], &(&1["symbol"] == "elmc_release_impl"))
    refute Enum.any?(linked["elmc_symbols"], &(&1["symbol"] == "app_main"))
  end

  test "put_linked_binary merges into stack report" do
    report = %{
      "code_size_indicators" => %{
        "linked_binary" => %{"available" => false}
      }
    }

    linked = LinkedBinaryReport.from_map(@sample_map)
    merged = StackEstimate.put_linked_binary(report, linked)

    assert merged["code_size_indicators"]["linked_binary"]["available"]
    assert merged["code_size_indicators"]["linked_binary"]["elmc_text_bytes"] == 0x600
  end

  test "enrich_file writes linked_binary when map exists" do
    tmp = Path.expand("tmp/linked_binary_report", __DIR__)
    build_dir = Path.join(tmp, "build/basalt")
    File.rm_rf!(tmp)
    File.mkdir_p!(build_dir)
    File.write!(Path.join(build_dir, "pebble-app.map"), @sample_map)

    report_path = Path.join(tmp, "elmc_stack_report.json")

    File.write!(
      report_path,
      Jason.encode!(%{"code_size_indicators" => %{"linked_binary" => %{available: false}}})
    )

    assert :ok = StackReport.enrich_file(report_path, tmp)
    contents = File.read!(report_path) |> Jason.decode!()
    assert contents["code_size_indicators"]["linked_binary"]["available"]
    assert contents["code_size_indicators"]["linked_binary"]["elmc_text_bytes"] == 0x600
  end

  test "flash_detail formats linked binary summary" do
    linked = %{
      "available" => true,
      "elf_size" => %{"text" => 20_392},
      "elmc_text_bytes" => 67_457
    }

    assert StackReport.flash_detail(linked) ==
             "flash text=20392 B, elmc symbols≈67457 B"
  end
end
