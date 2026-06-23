defmodule Ide.Debugger.WatchSubscriptionContractsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.ContractTestSupport
  alias Ide.Debugger.WatchSubscriptionContracts

  @speaker_main File.read!(
                  Path.join([
                    "priv",
                    "project_templates",
                    "watch_demo_speaker",
                    "src",
                    "Main.elm"
                  ])
                )

  test "finds Speaker.onFinished subscription call from parsed contract" do
    contract = ContractTestSupport.analyze_contract!(@speaker_main, "Main.elm")

    row =
      WatchSubscriptionContracts.find_subscription_call(
        contract,
        WatchSubscriptionContracts.speaker_finished()
      )

    assert row["target"] == "Speaker.onFinished"
    assert row["callback_constructor"] == "SpeakerFinished"

    assert WatchSubscriptionContracts.trigger_for_contract(
             contract,
             WatchSubscriptionContracts.speaker_finished()
           ) == "on_finished"
  end

  test "derives simulator payload suffix from msg constructor arg type" do
    contract = ContractTestSupport.analyze_contract!(@speaker_main, "Main.elm")

    assert WatchSubscriptionContracts.simulator_payload_suffix_for_trigger(
             contract,
             "on_finished",
             "SpeakerFinished"
           ) == "FinishedDone"
  end

  test "does not guess payload when callback constructor differs" do
    contract = ContractTestSupport.analyze_contract!(@speaker_main, "Main.elm")

    refute WatchSubscriptionContracts.simulator_payload_suffix_for_trigger(
             contract,
             "on_finished",
             "OtherMsg"
           )
  end
end
