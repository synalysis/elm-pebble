defmodule ElmEx.DebuggerContractSubscriptionWrapperTest do
  use ExUnit.Case, async: true

  alias ElmEx.DebuggerContract

  @subs_wrapper_call """
  module SubWrapper exposing (..)

  import Pebble.Events as Events
  import Pebble.Frame as Frame

  type Msg
      = MinuteChanged Int
      | FrameTick

  type alias Model =
      { animating : Bool }

  subscriptions model =
      addAnimationSub model <|
          Events.batch
              [ Events.onMinuteChange MinuteChanged ]

  addAnimationSub model subs =
      if model.animating then
          Sub.batch [ subs, Frame.every 500 FrameTick ]
      else
          subs

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      X.y []
  """

  test "extract_subscription_calls follows apply_left wrapper into local helper" do
    {:ok, snap} = DebuggerContract.analyze_source(@subs_wrapper_call, "SubWrapper.elm")
    calls = snap["debugger_contract"]["subscription_calls"]

    assert Enum.any?(
             calls,
             &match?(
               %{"event_kind" => "on_minute_change", "callback_constructor" => "MinuteChanged"},
               &1
             )
           )

    assert Enum.any?(
             calls,
             &match?(%{"event_kind" => "every", "callback_constructor" => "FrameTick"}, &1)
           )
  end
end
