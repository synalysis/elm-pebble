defmodule Ide.Debugger.DebuggerContractEventTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger
  alias Ide.Debugger.Types.DebuggerContractEventPayload

  @mini_elm """
  module ElmIntro exposing (..)

  type Msg = Tick

  init _ = ( {}, Cmd.none )

  update _ model = ( model, Cmd.none )

  view _ = Html.text "hi"
  """

  test "from_introspect builds summary payload from introspect snapshot" do
    ei = %{
      "module" => "ElmIntro",
      "msg_constructors" => ["Tick"],
      "update_case_branches" => ["Tick"],
      "view_case_branches" => ["view"],
      "view_tree" => %{"type" => "text", "children" => []},
      "init_model" => %{}
    }

    payload = DebuggerContractEventPayload.from_introspect(ei, "src/ElmIntro.elm", "watch", true)

    assert payload.module == "ElmIntro"
    assert payload.target == "watch"
    assert payload.msg_count == 1
    assert payload.view_outline == true
  end

  test "reload appends debugger.contract when source is Elm" do
    slug = "debugger_contract_event_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, state} =
             Debugger.reload(slug, %{
               "rel_path" => "src/ElmIntro.elm",
               "source_root" => "watch",
               "source" => @mini_elm
             })

    event = Enum.find(state.events, &(&1.type == "debugger.contract"))
    assert event
    assert event.payload.module == "ElmIntro"
    assert event.payload.rel_path == "src/ElmIntro.elm"
    assert is_integer(event.payload.msg_count)
  end
end
