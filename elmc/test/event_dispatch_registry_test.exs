defmodule Elmc.EventDispatchRegistryTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Pebble.SourceWriter.EventDispatch.{Emit, Registry}

  test "registry emits standard mask dispatch with tag lookup" do
    source = Emit.body()

    assert String.contains?(source, "int elmc_pebble_dispatch_hour(ElmcPebbleApp * app, int hour)")
    assert String.contains?(source, "ELMC_PEBBLE_SUB_HOUR")
    assert String.contains?(source, "elmc_pebble_dispatch_tag_value(app, tag, hour)")
  end

  test "registry emits record payload for frame and screen change" do
    source = Emit.body()

    assert String.contains?(source, "\"dtMs\", \"elapsedMs\", \"frame\"")
    assert String.contains?(source, "\"width\", \"height\", \"shape\", \"colorMode\"")
    assert String.contains?(source, "ELMC_PEBBLE_MODE_WATCHFACE")
  end

  test "registry emits custom button and dictation handlers" do
    source = Emit.body()

    assert String.contains?(source, "elmc_worker_button_raw_msg_tag")
    assert String.contains?(source, "elmc_pebble_dispatch_tag_payload(app, tag, result_payload)")
    assert String.contains?(source, "elmc_pebble_button_event")
    assert String.contains?(source, "elmc_pebble_is_subscribed")
    assert String.contains?(source, "elmc_pebble_dispatch_appmessage")
    assert String.contains?(source, "elmc_pebble_dispatch_storage_string")
    assert String.contains?(source, "elmc_pebble_dispatch_random_int")
  end

  test "emit includes tick with payload branch when Msg arity requires it" do
    with_payload =
      Emit.body(%{msg: %{tick_has_payload?: true}})

    without_payload =
      Emit.body(%{msg: %{tick_has_payload?: false}})

    assert String.contains?(with_payload, "elmc_pebble_tick")
    assert String.contains?(with_payload, "elmc_msg_constructor_arity")
    assert String.contains?(without_payload, "elmc_pebble_tick")
    refute String.contains?(without_payload, "elmc_msg_constructor_arity")
  end

  test "registry covers every declared entry" do
    for %{fn: fn_name} <- Registry.entries() do
      assert String.contains?(Emit.body(), fn_name)
    end
  end

  test "emit includes app-message decode and optional compass" do
    with_compass =
      Emit.body(%{
        msg: %{
          value_decode_cases: "          case 1: *out_tag = 1; return 0;",
          key_decode_cases: "",
          tick_has_payload?: false
        },
        compass_events?: true
      })

    without_compass =
      Emit.body(%{
        msg: %{value_decode_cases: "", key_decode_cases: "", tick_has_payload?: false},
        compass_events?: false
      })

    assert String.contains?(with_compass, "elmc_pebble_msg_from_appmessage")
    assert String.contains?(with_compass, "elmc_pebble_dispatch_compass_heading")
    refute String.contains?(without_compass, "elmc_pebble_dispatch_compass_heading")
  end

  test "emit includes worker view/cmd host API wrappers" do
    source = Emit.body()

    assert String.contains?(source, "elmc_pebble_take_cmd")
    assert String.contains?(source, "elmc_pebble_pending_cmd_count")
    assert String.contains?(source, "elmc_pebble_view_commands_from")
  end
end
