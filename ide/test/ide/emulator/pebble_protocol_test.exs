defmodule Ide.Emulator.PebbleProtocolTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.PebbleProtocol.{CRC32, Frame, Packets}

  describe "Frame" do
    test "round-trips outer framing (big-endian length and endpoint)" do
      payload = <<0x01, 0xAA>>
      framed = Frame.encode(52, payload)
      assert {:ok, parsed, ""} = Frame.parse(framed)
      assert parsed.endpoint == 52
      assert parsed.payload == payload
    end

    test "parse_many preserves order" do
      a = Frame.encode(1, <<1>>)
      b = Frame.encode(2, <<2, 3>>)
      {frames, rest} = Frame.parse_many(a <> b)
      assert length(frames) == 2
      assert Enum.at(frames, 0).endpoint == 1
      assert Enum.at(frames, 1).endpoint == 2
      assert rest == <<>>
    end
  end

  describe "CRC32.stm32/1" do
    test "matches libpebble stm32_crc reference vectors (pebble-tool Python)" do
      # Reference: libpebble2.util.stm32_crc.crc32 via pebble SDK Python
      assert CRC32.stm32(<<>>) == 0xFFFFFFFF
      assert CRC32.stm32(<<0, 1, 2, 3>>) == 0x76DBF7C7
      assert CRC32.stm32(<<0, 1, 2, 3, 4>>) == 0x13647581

      blob = :binary.list_to_bin(Enum.to_list(0..126))
      assert CRC32.stm32(blob) == 0xF86C138F
    end
  end

  describe "Packets" do
    test "app_fetch_request decode matches LE app_id" do
      uuid_hex = String.replace("3278ae24-9885-427f-90e7-791ac2450e78", "-", "")
      {:ok, raw_uuid} = Base.decode16(uuid_hex, case: :mixed)

      blob =
        <<0x01, raw_uuid::binary, 42::little-32>>

      assert {:ok, %{uuid: uuid, app_id: 42}} = Packets.decode_app_fetch_request(blob)
      assert String.downcase(uuid) == String.downcase("3278ae24-9885-427f-90e7-791ac2450e78")
    end

    test "golden app_run_state_start payload (libpebble2.serialise strip)" do
      {ep, payload} = Packets.app_run_state_start("3278ae24-9885-427f-90e7-791ac2450e78")

      assert ep == 52
      # libpebble2: AppRunStateStart serialise inner uuid after command byte
      assert Base.encode16(payload, case: :lower) ==
               "013278ae249885427f90e7791ac2450e78"
    end

    test "golden app_fetch_start_response" do
      {ep, payload} = Packets.app_fetch_start_response()
      assert ep == Packets.endpoint(:app_fetch)
      assert payload == <<0x01, 0x01>>
    end

    test "golden BlobDB app metadata insert" do
      metadata = %{
        uuid: "6e5066e4-2709-4eb2-97a6-c8ff29b643bf",
        flags: 1,
        icon_resource_id: 0,
        app_version_major: 1,
        app_version_minor: 0,
        sdk_version_major: 3,
        sdk_version_minor: 0,
        app_name: "WF Analog"
      }

      {ep, payload} = Packets.blob_insert_app(0x1234, metadata)

      assert ep == Packets.endpoint(:blob_db)

      expected =
        "01341202106e5066e427094eb297a6c8ff29b643bf7e006e5066e427094eb297a6c8ff29b643bf0100000000000000010003000000574620416e616c6f67" <>
          String.duplicate("00", 87)

      assert byte_size(payload) == 149
      assert Base.encode16(payload, case: :lower) == expected
    end

    test "golden BlobDB app metadata delete" do
      {ep, payload} = Packets.blob_delete_app(0x1235, "6e5066e4-2709-4eb2-97a6-c8ff29b643bf")

      assert ep == Packets.endpoint(:blob_db)

      assert Base.encode16(payload, case: :lower) ==
               "04351202106e5066e427094eb297a6c8ff29b643bf"
    end

    test "golden PutBytes sequences (aligned with libpebble2.PutBytesApp serialisation)" do
      {_, p1} = Packets.putbytes_app_init(100, Packets.object_type(:binary), 42)

      assert Base.encode16(p1, case: :lower) == "0100000064850000002a"

      {_, p2} = Packets.putbytes_put(0xABCDEF01, "abc")

      assert Base.encode16(p2, case: :lower) ==
               "02abcdef0100000003616263"

      crc = CRC32.stm32(<<0x00, 0x01>>)
      {_, p3} = Packets.putbytes_commit(99, crc)
      assert byte_size(p3) == 1 + 4 + 4
    end

    test "putbytes_response decode acknowledges cookie" do
      assert {:ok, %{ack?: true, cookie: 123}} =
               Packets.decode_putbytes_response(<<1, 0, 0, 0, 123>>)

      assert {:ok, nack} = Packets.decode_putbytes_response(<<2, 0, 0, 0, 1>>)
      assert Packets.putbytes_ack?(nack, nil) == {:error, {:nack, 1}}
    end
  end
end
