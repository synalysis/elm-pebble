defmodule Elmx.MessageDecodeTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.MessageDecode

  test "decode nullary message as atom" do
    assert MessageDecode.decode("Increment") == :Increment
  end

  test "decode message with integer payload" do
    assert MessageDecode.decode("RandomGenerated 12345") == {:RandomGenerated, 12_345}
    assert MessageDecode.decode("Tick 7") == {:Tick, 7}
  end

  test "decode message with True or False suffix" do
    assert MessageDecode.decode("ClockStyle24h True") == {:ClockStyle24h, true}
    assert MessageDecode.decode("HealthSupported False") == {:HealthSupported, false}
  end

  test "decode FrameTick with JSON payload" do
    msg = "FrameTick " <> Jason.encode!(%{"dtMs" => 16, "elapsedMs" => 32, "frame" => 2})
    assert MessageDecode.decode(msg) == {:FrameTick, %{"dtMs" => 16, "elapsedMs" => 32, "frame" => 2}}
  end

  test "decode bare FrameTick uses default frame map" do
    assert MessageDecode.decode("FrameTick") ==
             {:FrameTick, MessageDecode.default_frame_payload()}
  end

  test "decode message with string payload" do
    assert MessageDecode.decode("CurrentTimeString 12:34") == {:CurrentTimeString, "12:34"}
    assert MessageDecode.decode("StorageStringLoaded saved") == {:StorageStringLoaded, "saved"}
  end

  test "decode message with nested union constructor payload" do
    assert MessageDecode.decode("SpeakerFinished FinishedDone") ==
             {:SpeakerFinished, :FinishedDone}
  end

  test "decode FromPhone wire message_value into tagged tuple msg" do
    wire = %{
      "ctor" => "FromPhone",
      "args" => [
        %{
          "ctor" => "ProvideWebSocketStatus",
          "args" => [%{"ctor" => "Open", "args" => []}, "connected"]
        }
      ]
    }

    assert MessageDecode.decode("FromPhone", wire) ==
             {:FromPhone, {:ProvideWebSocketStatus, :Open, "connected"}}
  end

  test "decode FromPhone parenthetical string message" do
    assert MessageDecode.decode("FromPhone (ProvideWebSocketStatus Open connected)") ==
             {:FromPhone, {:ProvideWebSocketStatus, :Open, "connected"}}
  end

  test "decode nested union wire payload for weather condition" do
    wire = %{
      "ctor" => "FromPhone",
      "args" => [
        %{"ctor" => "ProvideCondition", "args" => [%{"ctor" => "Snow", "args" => []}]}
      ]
    }

    assert MessageDecode.decode("FromPhone (ProvideCondition Snow)", wire) ==
             {:FromPhone, {:ProvideCondition, :Snow}}
  end

  test "decode GotLocale Ok wire record payload" do
    wire = %{
      "ctor" => "GotLocale",
      "args" => [%{"ctor" => "Ok", "args" => [%{"locale" => "en-US"}]}]
    }

    assert MessageDecode.decode("GotLocale", wire) ==
             {:GotLocale, {:Ok, %{"locale" => "en-US"}}}
  end

  test "decode FromWatch RequestWeather with elmc wire location ctor" do
    wire = %{
      "ctor" => "FromWatch",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [
            %{
              "ctor" => "RequestWeather",
              "args" => [%{"$ctor" => "CurrentLocation", "$args" => []}]
            }
          ]
        }
      ]
    }

    assert MessageDecode.decode("FromWatch", wire) ==
             {:FromWatch, {:Ok, {:RequestWeather, :CurrentLocation}}}
  end

  test "decode GotConnectivity wire variant payload" do
    wire = %{"ctor" => "GotConnectivity", "args" => [%{"ctor" => "Online", "args" => []}]}

    assert MessageDecode.decode("GotConnectivity", wire) == {:GotConnectivity, :Online}
  end

  test "decode GotCalendar Ok wire list payload" do
    wire = %{
      "ctor" => "GotCalendar",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [
            [
              %{
                "id" => "standup",
                "title" => "Team Sync",
                "startMillis" => 32_400_000,
                "endMillis" => 32_760_000,
                "allDay" => false
              }
            ]
          ]
        }
      ]
    }

    assert MessageDecode.decode("GotCalendar", wire) ==
             {:GotCalendar, {:Ok, [%{"id" => "standup", "title" => "Team Sync", "startMillis" => 32_400_000, "endMillis" => 32_760_000, "allDay" => false}]}}
  end

  test "decode GotStorage Ok StringValue wire payload" do
    wire = %{
      "ctor" => "GotStorage",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [%{"ctor" => "StringValue", "args" => ["light"]}]
        }
      ]
    }

    assert MessageDecode.decode("GotStorage", wire) ==
             {:GotStorage, {:Ok, {:StringValue, "light"}}}
  end

  test "decode GotPreference Ok pair wire payload" do
    wire = %{
      "ctor" => "GotPreference",
      "args" => [%{"ctor" => "Ok", "args" => [{"units", "imperial"}]}]
    }

    assert MessageDecode.decode("GotPreference", wire) ==
             {:GotPreference, {:Ok, {"units", "imperial"}}}
  end

  test "decode GotWeather Ok Current wire payload" do
    info = %{
      "temperatureC" => 22,
      "condition" => %{"ctor" => "Rain", "args" => []}
    }

    wire = %{
      "ctor" => "GotWeather",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [
            %{"ctor" => "Current", "args" => [info]}
          ]
        }
      ]
    }

    assert MessageDecode.decode("GotWeather", wire) ==
             {:GotWeather, {:Ok, {:Current, %{"temperatureC" => 22, "condition" => :Rain}}}}
  end

  test "decode GotToken Ok wire payload" do
    wire = %{
      "ctor" => "GotToken",
      "args" => [%{"ctor" => "Ok", "args" => ["timeline-token"]}]
    }

    assert MessageDecode.decode("GotToken", wire) == {:GotToken, {:Ok, "timeline-token"}}
  end

  test "decode PinInserted Ok unit wire payload" do
    wire = %{
      "ctor" => "PinInserted",
      "args" => [%{"ctor" => "Ok", "args" => [%{"ctor" => "()", "args" => []}]}]
    }

    assert MessageDecode.decode("PinInserted", wire) == {:PinInserted, {:Ok, nil}}
  end

  test "decode LifecycleChanged Ready wire payload" do
    wire = %{
      "ctor" => "LifecycleChanged",
      "args" => [%{"ctor" => "Ready", "args" => []}]
    }

    assert MessageDecode.decode("LifecycleChanged", wire) ==
             {:LifecycleChanged, :Ready}
  end

  test "decode ConfigurationClosed Nothing wire payload" do
    wire = %{
      "ctor" => "ConfigurationClosed",
      "args" => [%{"ctor" => "Nothing", "args" => []}]
    }

    assert MessageDecode.decode("ConfigurationClosed", wire) == {:ConfigurationClosed, :Nothing}
  end

  test "decode GotPosition Ok wire record payload" do
    location = %{"latitude" => 12.345, "longitude" => -98.765, "accuracy" => 25.0}

    wire = %{
      "ctor" => "GotPosition",
      "args" => [%{"ctor" => "Ok", "args" => [location]}]
    }

    assert MessageDecode.decode("GotPosition", wire) == {:GotPosition, {:Ok, location}}
  end

  test "decode GotEnvironment Ok wire payload" do
    info = %{
      "sun" => %{"sunriseMin" => 360, "sunsetMin" => 1140, "polarDay" => false},
      "moon" => %{"phaseE6" => 750_000}
    }

    wire = %{
      "ctor" => "GotEnvironment",
      "args" => [%{"ctor" => "Ok", "args" => [info]}]
    }

    assert MessageDecode.decode("GotEnvironment", wire) ==
             {:GotEnvironment, {:Ok, info}}
  end

  test "decode GotBattery Ok wire record payload" do
    wire = %{
      "ctor" => "GotBattery",
      "args" => [
        %{
          "ctor" => "Ok",
          "args" => [%{"percent" => 55, "charging" => true}]
        }
      ]
    }

    assert MessageDecode.decode("GotBattery", wire) ==
             {:GotBattery, {:Ok, %{"percent" => 55, "charging" => true}}}
  end

  test "decode MinuteChanged wire value does not wrap with full message label" do
    wire = %{"ctor" => "MinuteChanged", "args" => [6]}

    assert MessageDecode.decode("MinuteChanged 6", wire) == {:MinuteChanged, 6}
  end

  test "decode bare CurrentDateTime record map using parent message label" do
    wire = %{
      "year" => 2026,
      "month" => 6,
      "day" => 1,
      "hour" => 22,
      "minute" => 5,
      "second" => 10,
      "utcOffsetMinutes" => 120,
      "dayOfWeek" => %{"ctor" => "Monday", "args" => []}
    }

    assert {:CurrentDateTime, payload} = MessageDecode.decode("CurrentDateTime", wire)
    assert Map.get(payload, "dayOfWeek") == :Monday
    assert Map.get(payload, "minute") == 5
  end

  test "decode CurrentDateTime wire record matches parent ctor" do
    wire = %{
      "ctor" => "CurrentDateTime",
      "args" => [
        %{
          "year" => 2026,
          "month" => 6,
          "day" => 1,
          "hour" => 22,
          "minute" => 5,
          "second" => 10,
          "utcOffsetMinutes" => 120,
          "dayOfWeek" => %{"ctor" => "Monday", "args" => []}
        }
      ]
    }

    assert {:CurrentDateTime, payload} = MessageDecode.decode("CurrentDateTime", wire)
    assert is_map(payload)
    assert Map.get(payload, "minute") == 5
  end

  test "decode CatalogReceived Ok string payload from inner wire value" do
    wire = %{"ctor" => "Ok", "args" => ["{\"page1-0\": {}}"]}

    assert MessageDecode.decode("CatalogReceived", wire) ==
             {:CatalogReceived, {:Ok, "{\"page1-0\": {}}"}}
  end

  test "non-empty wire message_value takes precedence over string message" do
    wire = %{
      "ctor" => "FromPhone",
      "args" => [%{"ctor" => "ProvideBattery", "args" => [88, true]}]
    }

    assert MessageDecode.decode("FromPhone (ignored)", wire) ==
             {:FromPhone, {:ProvideBattery, 88, true}}
  end
end
