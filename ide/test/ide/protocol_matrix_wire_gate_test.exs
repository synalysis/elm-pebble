defmodule Ide.ProtocolMatrixWireGateTest do
  @moduledoc """
  CI-friendly gate for the protocol-matrix wire path that host TEA inject skips.

  Covers generated C value-encode (full payloads, nameless records), the C
  round-trip harness, template send sites, and the pebble template dispatch that
  prefers `companion_protocol_encode_watch_to_phone_value`.

  Does not replace the opt-in live emulator walk
  (`Ide.Emulator.ProtocolMatrixLiveTest`); that still needs QEMU.
  """
  use ExUnit.Case, async: false

  alias Ide.CompanionProtocolCTestHarness
  alias Ide.CompanionProtocolGenerator

  @ide_root Path.expand("../..", __DIR__)
  @template_root Path.join(@ide_root, "priv/project_templates/companion_demo_protocol_matrix")
  @types Path.join(@template_root, "protocol/src/Companion/Types.elm")
  @internal Path.join(@template_root, "protocol/src/Companion/Internal.elm")
  @main Path.join(@template_root, "src/Main.elm")
  @pebble_template Path.join(@ide_root, "priv/pebble_app_template/src/c/pebble_app_template.c")

  # WatchToPhone / PhoneToWatch wire tags from Companion.Internal.
  @watch_tags [
    {"Ping", 2},
    {"SendColor", 3},
    {"SendMeasure", 4},
    {"SendPoint", 5},
    {"SendCounts", 6},
    {"RequestPhoneExtras", 7}
  ]

  @phone_tags [201, 202, 203, 204, 205, 206, 207, 208, 209]

  setup do
    assert File.exists?(@types)
    assert File.exists?(@internal)
    assert File.exists?(@main)
    assert File.exists?(@pebble_template)
    :ok
  end

  test "template Internal.elm keeps the full matrix wire tag table" do
    internal = File.read!(@internal)

    Enum.each(@watch_tags, fn {name, tag} ->
      assert Regex.match?(~r/#{Regex.escape(name)}[^\n]*\n\s+#{tag}\b/, internal),
             "missing WatchToPhone tag #{tag} for #{name}"
    end)

    Enum.each(@phone_tags, fn tag ->
      assert internal =~ "Encode.int #{tag}",
             "missing PhoneToWatch Encode.int #{tag}"
    end)
  end

  test "template Main.elm sends every matrix constructor via sendWatchToPhone" do
    main = File.read!(@main)

    assert main =~ "CompanionWatch.sendWatchToPhone Ping"
    assert main =~ "CompanionWatch.sendWatchToPhone (SendColor Red)"
    assert main =~ "CompanionWatch.sendWatchToPhone (SendMeasure (Liters 3))"
    assert main =~ "CompanionWatch.sendWatchToPhone (SendPoint { x = 1, y = 2 })"
    assert main =~ "CompanionWatch.sendWatchToPhone (SendCounts [ 1, 2, 3 ])"
    assert main =~ "CompanionWatch.sendWatchToPhone RequestPhoneExtras"

    # Unexpected replies while Running must not Fail the active case.
    assert main =~ "not this case failing"
  end

  test "pebble template prefers value encode when companion-send carries a message" do
    template = File.read!(@pebble_template)

    assert template =~ "companion_protocol_encode_watch_to_phone_value"
    assert template =~ ~r/message\s*!=\s*NULL/
    assert template =~ "companion_protocol_encode_watch_to_phone(iter, request_tag, request_value)"
  end

  test "generated value encoder covers enum/union/record/list payloads for the matrix" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "protocol-matrix-wire-gate-#{System.unique_integer([:positive])}"
      )

    header = Path.join(tmp, "companion_protocol.h")
    source = Path.join(tmp, "companion_protocol.c")
    js = Path.join(tmp, "companion-protocol.js")

    try do
      File.mkdir_p!(tmp)

      assert :ok = CompanionProtocolGenerator.generate(@types, header, source, js)

      generated_c = File.read!(source)
      generated_js = File.read!(js)

      assert generated_c =~
               "bool companion_protocol_encode_watch_to_phone_value(DictionaryIterator *iter, ElmcValue *message)"

      assert generated_c =~ "elmc_record_get_index("
      refute generated_c =~ ~r/elmc_record_get\([^,]+,\s*"/

      assert generated_c =~ "COMPANION_PROTOCOL_KEY_SEND_COLOR_FIELD1"
      assert generated_c =~ "COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_TAG"
      assert generated_c =~ "COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_VALUE"
      assert generated_c =~ "COMPANION_PROTOCOL_KEY_SEND_POINT_FIELD1_X"
      assert generated_c =~ "COMPANION_PROTOCOL_KEY_SEND_POINT_FIELD1_Y"
      assert generated_c =~ "COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_COUNT"

      # Dict / list scratch arrays must be zero-initialized before elmc_tuple2_take.
      assert generated_c =~ ~r/ElmcValue \*\w+_pairs\[\d+\] = \{0\};/
      assert generated_c =~ ~r/ElmcValue \*\w+_items\[\d+\] = \{0\};/

      for kind <- [
            "EchoColor",
            "EchoMeasure",
            "EchoPoint",
            "EchoCounts",
            "PushBool",
            "PushString",
            "PushPoints",
            "PushLabels"
          ] do
        assert generated_js =~ ~s|case "#{kind}":|,
               "JS phone→watch remapper missing #{kind}"
      end
    after
      File.rm_rf(tmp)
    end
  end

  test "C harness round-trips every watch→phone constructor including nameless Point" do
    if is_nil(System.find_executable("cc")) do
      flunk("cc not available")
    else
      assert :ok = CompanionProtocolCTestHarness.run_roundtrip!(@types)
    end
  end

  test "embedded pypkjs accepts cstring dict keys used by PushLabels" do
    script = Path.join(@ide_root, "priv/python/embedded_pypkjs.py")
    assert File.exists?(script)
    assert File.read!(script) =~ "try_appmessage_int"
    assert File.read!(script) =~ "valid and must not be forced through"
  end
end

