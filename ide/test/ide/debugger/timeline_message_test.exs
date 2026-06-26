defmodule Ide.Debugger.TimelineMessageTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.TimelineMessage

  test "format includes structured payload" do
    value = %{"ctor" => "CurrentDateTime", "args" => [%{"minute" => 7, "hour" => 8}]}

    assert TimelineMessage.format("CurrentDateTime", value) ==
             "CurrentDateTime { hour = 8, minute = 7 }"
  end

  test "message_value_for_step parses minute and json payloads" do
    assert TimelineMessage.message_value_for_step("MinuteChanged 42") ==
             {"MinuteChanged", %{"ctor" => "MinuteChanged", "args" => [42]}}

    assert {"CurrentDateTime", %{"ctor" => "CurrentDateTime", "args" => [%{} = payload]}} =
             TimelineMessage.message_value_for_step(
               "CurrentDateTime #{Jason.encode!(%{"minute" => 7, "hour" => 8})}"
             )

    assert payload["minute"] == 7
    assert payload["hour"] == 8
  end

  test "message_value_for_step parses nested protocol constructor payloads" do
    assert TimelineMessage.message_value_for_step("SpeakerFinished FinishedDone") ==
             {"SpeakerFinished",
              %{
                "ctor" => "SpeakerFinished",
                "args" => [%{"ctor" => "FinishedDone", "args" => []}]
              }}
  end

  test "format ignores constructor-only trailing whitespace" do
    assert TimelineMessage.format("MinuteChanged ", nil) == "MinuteChanged"
  end

  test "format decodes tangram PhoneToWatch protocol payloads" do
    provide_figure =
      %{
        "ctor" => "FromPhone",
        "args" => [%{"ctor" => "ProvideFigure", "args" => [0]}]
      }

    assert TimelineMessage.format("FromPhone", provide_figure) ==
             "FromPhone (ProvideFigure 0)"

    provide_piece =
      %{
        "ctor" => "FromPhone",
        "args" => [
          %{
            "ctor" => "ProvidePiece",
            "args" => [0, [0, 4, -13, -13, 13, -13, 13, -38, -13, -38]]
          }
        ]
      }

    assert TimelineMessage.format("FromPhone", provide_piece) ==
             "FromPhone (ProvidePiece 0 [0,4,-13,-13,13,-13,13,-38,-13,-38])"

    begin_figure =
      %{
        "ctor" => "FromPhone",
        "args" => [%{"ctor" => "BeginFigure", "args" => [0]}]
      }

    assert TimelineMessage.format("FromPhone", begin_figure) ==
             "FromPhone (BeginFigure 0)"

    end_figure =
      %{
        "ctor" => "FromPhone",
        "args" => [%{"ctor" => "EndFigure", "args" => [0]}]
      }

    assert TimelineMessage.format("FromPhone", end_figure) == "FromPhone (EndFigure 0)"
  end

  test "format parenthesizes nested protocol constructor arguments" do
    value = %{
      "ctor" => "FromPhone",
      "args" => [
        %{
          "ctor" => "ProvideTemperature",
          "args" => [%{"ctor" => "Celsius", "args" => [28]}]
        }
      ]
    }

    assert TimelineMessage.format("FromPhone", value) ==
             "FromPhone (ProvideTemperature (Celsius 28))"
  end

  test "format protocol matrix wire values with Elm-style display" do
    assert TimelineMessage.format("FromPhone", %{
             "ctor" => "FromPhone",
             "args" => [%{"x" => 1, "y" => 2}]
           }) == "FromPhone ({ x = 1, y = 2 })"

    assert TimelineMessage.format("FromPhone", %{
             "ctor" => "FromPhone",
             "args" => [%{"ctor" => "EchoPoint", "args" => [%{"x" => 1, "y" => 2}]}]
           }) == "FromPhone (EchoPoint { x = 1, y = 2 })"

    assert TimelineMessage.format("PushBool", %{
             "ctor" => "PushBool",
             "args" => [true]
           }) == "PushBool True"

    assert TimelineMessage.format("PushBool", %{
             "ctor" => "PushBool",
             "args" => [false]
           }) == "PushBool False"

    assert TimelineMessage.format("PushLabels", %{
             "ctor" => "PushLabels",
             "args" => [{:elmx_dict, %{"k" => 9}}]
           }) == "PushLabels HashMap.fromList [(\"k\",9)]"

    assert TimelineMessage.format("SendPoint", %{
             "ctor" => "SendPoint",
             "args" => [%{"x" => 1, "y" => 2}]
           }) == "SendPoint { x = 1, y = 2 }"

    assert TimelineMessage.format("EchoPoint", %{
             "ctor" => "EchoPoint",
             "args" => [%{"x" => 1, "y" => 2}]
           }) == "EchoPoint { x = 1, y = 2 }"
  end
end
