defmodule Ide.Debugger.ProtocolTxRxPayloadTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  alias Ide.Debugger.ElmIntrospect

  @phone_to_watch_elm """
  module Bridge exposing (..)

  import Companion.Phone as CompanionPhone
  import Companion.Types exposing (PhoneToWatch(..))

  type Msg = GotPing Int

  init _ =
      ( {}, CompanionPhone.sendPhoneToWatch (Ping 1) )

  update msg model =
      case msg of
          GotPing _ ->
              ( model, Cmd.none )
  """

  test "introspect init_cmd_calls include sendPhoneToWatch for protocol bridge mapping" do
    assert {:ok, %{"elm_introspect" => ei}} =
             ElmIntrospect.analyze_source(@phone_to_watch_elm, "Bridge.elm")

    assert Enum.any?(ei["init_cmd_calls"], fn row ->
             (row["name"] == "sendPhoneToWatch" or row[:name] == "sendPhoneToWatch") and
               is_binary(row["callback_constructor"] || row[:callback_constructor])
           end)
  end

  test "companion reload appends protocol tx/rx payloads with typed from/to/message" do
    slug = "protocol_reload_tx_rx_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, state} =
             Debugger.reload(slug, %{
               "rel_path" => "companion/src/Bridge.elm",
               "source_root" => "companion",
               "source" => @phone_to_watch_elm,
               "reason" => "protocol_reload_test"
             })

    tx = Enum.find(state.events, &(&1.type == "debugger.protocol_tx"))
    rx = Enum.find(state.events, &(&1.type == "debugger.protocol_rx"))

    assert tx && rx
    assert tx.payload.from == "watch"
    assert tx.payload.to == "companion"
    assert is_binary(tx.payload.message)
    assert String.starts_with?(tx.payload.message, "Reloaded:")
    assert tx.payload.message == rx.payload.message
  end
end
