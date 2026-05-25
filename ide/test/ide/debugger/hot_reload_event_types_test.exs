defmodule Ide.Debugger.HotReloadEventTypesTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger

  @mini_elm """
  module HotReload exposing (..)

  type Msg = Tick

  init _ = ( {}, Cmd.none )

  update _ model = ( model, Cmd.none )
  """

  test "reload appends typed hot_reload event payload" do
    slug = "hot_reload_event_#{System.unique_integer([:positive])}"
    on_exit(fn -> Debugger.forget_project(slug) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, state} =
             Debugger.reload(slug, %{
               "rel_path" => "src/HotReload.elm",
               "source_root" => "watch",
               "source" => @mini_elm,
               "reason" => "type_test"
             })

    reload_event = Enum.find(state.events, &(&1.type == "debugger.reload"))
    assert reload_event

    assert reload_event.payload.reason == "type_test"
    assert reload_event.payload.rel_path == "src/HotReload.elm"
    assert reload_event.payload.source_root == "watch"
    assert is_binary(reload_event.payload.revision)
  end
end
