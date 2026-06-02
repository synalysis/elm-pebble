defmodule Ide.Debugger.MessageInEventTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  alias Ide.Debugger.Types.MessageInEventPayload

  @mini_elm """
  module MessageInEvent exposing (..)

  type Msg = Tick

  init _ = ( {}, Cmd.none )

  update _ model = ( model, Cmd.none )
  """

  test "from_message builds init and update payloads" do
    payload = MessageInEventPayload.from_message("watch", "Tick", "provided")
    assert payload.target == "watch"
    assert payload.message == "Tick"
    assert payload.message_source == "provided"
  end

  test "step appends debugger.update_in with MessageInEventPayload shape" do
    slug = "message_in_event_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               "rel_path" => "src/MessageInEvent.elm",
               "source_root" => "watch",
               "source" => @mini_elm
             })

    assert {:ok, state} =
             Debugger.step(slug, %{"target" => "watch", "message" => "Tick", "count" => 1})

    update_event = Enum.find(state.events, &(&1.type == "debugger.update_in"))
    assert update_event.payload.message == "Tick"
    assert update_event.payload.target == "watch"
  end
end
