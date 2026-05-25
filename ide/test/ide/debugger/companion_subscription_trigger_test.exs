defmodule Ide.Debugger.CompanionSubscriptionTriggerTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.CompanionSubscriptionTrigger

  test "companion_trigger? matches module-qualified battery subscription triggers" do
    assert CompanionSubscriptionTrigger.companion_trigger?("Battery.onBattery")
    assert CompanionSubscriptionTrigger.companion_trigger?("Pebble.Companion.Battery.onBattery")
    assert CompanionSubscriptionTrigger.companion_trigger?("on_battery")
    refute CompanionSubscriptionTrigger.companion_trigger?("onBattery")
    refute CompanionSubscriptionTrigger.companion_trigger?("PebbleSystem.onBatteryChange")
  end

  test "form_data builds battery fields for introspect event_kind triggers" do
    state = %{simulator_settings: %{"battery_percent" => 42, "charging" => true}}

    assert %{"payload_kind" => "companion_bridge", "companion_field_percent" => "42"} =
             CompanionSubscriptionTrigger.form_data(state, "on_battery", "GotBattery")
  end

  test "form_data builds battery fields from simulator settings" do
    state = %{simulator_settings: %{"battery_percent" => 42, "charging" => true}}

    assert %{
             "payload_kind" => "companion_bridge",
             "companion_contract" => "battery",
             "message_constructor" => "GotBattery",
             "companion_field_percent" => "42",
             "companion_field_charging" => "true"
           } = CompanionSubscriptionTrigger.form_data(state, "Battery.onBattery", "GotBattery")
  end

  test "message_value builds structured GotBattery Ok payload" do
    params = %{
      "companion_contract" => "battery",
      "message_constructor" => "GotBattery",
      "result" => "Ok",
      "companion_field_percent" => "55",
      "companion_field_charging" => "true"
    }

    assert %{
             "ctor" => "GotBattery",
             "args" => [
               %{
                 "ctor" => "Ok",
                 "args" => [%{"percent" => 55, "charging" => true}]
               }
             ]
           } = CompanionSubscriptionTrigger.message_value(params)
  end

  test "message_value builds structured GotBattery Err payload" do
    params = %{
      "companion_contract" => "battery",
      "message_constructor" => "GotBattery",
      "result" => "Err",
      "error_message" => "Battery unavailable"
    }

    assert %{
             "ctor" => "GotBattery",
             "args" => [
               %{
                 "ctor" => "Err",
                 "args" => ["Battery unavailable"]
               }
             ]
           } = CompanionSubscriptionTrigger.message_value(params)
  end

  test "form_data builds calendar fields from simulator settings" do
    state = %{
      simulator_settings: %{
        "calendar_events" => [
          %{
            "id" => "meeting",
            "title" => "Standup",
            "startMillis" => 100,
            "endMillis" => 200,
            "allDay" => false
          }
        ]
      }
    }

    assert %{
             "payload_kind" => "companion_bridge",
             "companion_contract" => "calendar",
             "companion_field_id" => "meeting",
             "companion_field_title" => "Standup",
             "companion_field_startMillis" => "100",
             "companion_field_endMillis" => "200"
           } = CompanionSubscriptionTrigger.form_data(state, "on_calendar", "GotCalendarPush")
  end

  test "message_value builds onCalendar list payload from calendar event fields" do
    params = %{
      "companion_contract" => "calendar",
      "message_constructor" => "GotCalendarPush",
      "result" => "Ok",
      "trigger" => "Calendar.onCalendar",
      "companion_field_id" => "meeting",
      "companion_field_title" => "Standup",
      "companion_field_location" => "",
      "companion_field_startMillis" => "100",
      "companion_field_endMillis" => "200",
      "companion_field_allDay" => "false"
    }

    assert %{
             "ctor" => "GotCalendarPush",
             "args" => [
               %{
                 "ctor" => "Ok",
                 "args" => [
                   [
                     %{
                       "id" => "meeting",
                       "title" => "Standup",
                       "startMillis" => 100,
                       "endMillis" => 200,
                       "allDay" => false
                     }
                   ]
                 ]
               }
             ]
           } = CompanionSubscriptionTrigger.message_value(params)
  end

  test "message_value builds onCurrent Maybe payload from calendar event fields" do
    params = %{
      "companion_contract" => "calendar",
      "message_constructor" => "GotNext",
      "result" => "Ok",
      "trigger" => "Calendar.onCurrent",
      "companion_field_id" => "meeting",
      "companion_field_title" => "Standup",
      "companion_field_startMillis" => "100",
      "companion_field_endMillis" => "200",
      "companion_field_allDay" => "true"
    }

    assert %{
             "ctor" => "GotNext",
             "args" => [
               %{
                 "ctor" => "Ok",
                 "args" => [
                   %{
                     "ctor" => "Just",
                     "args" => [
                       %{
                         "id" => "meeting",
                         "title" => "Standup",
                         "startMillis" => 100,
                         "endMillis" => 200,
                         "allDay" => true
                       }
                     ]
                   }
                 ]
               }
             ]
           } = CompanionSubscriptionTrigger.message_value(params)
  end

  test "message_value builds connectivity payload without Result wrapper" do
    params = %{
      "companion_contract" => "network",
      "message_constructor" => "GotConnectivity",
      "companion_field_online" => "false"
    }

    assert %{
             "ctor" => "GotConnectivity",
             "args" => [%{"ctor" => "Offline", "args" => []}]
           } = CompanionSubscriptionTrigger.message_value(params)
  end
end
