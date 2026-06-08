defmodule Ide.Debugger.ConfigurationCallbackProbeTest do
  use Ide.DataCase, async: false

  @moduletag :integration
  @moduletag timeout: 180_000

  alias Ide.Debugger.CompanionBridge
  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.ConfigurationSave

  test "phone reload keeps configuration subscription callback after watch reload" do
    slug = "cfg-probe-#{System.unique_integer([:positive])}"

    {:ok, project} =
      Ide.Projects.create_project(%{
        "name" => "CfgProbe",
        "slug" => slug,
        "target_type" => "app",
        "template" => "watchface-yes"
      })

    root = Ide.Projects.project_workspace_path(project)
    phone_source = File.read!(Path.join([root, "phone", "src", "CompanionApp.elm"]))
    watch_source = File.read!(Path.join([root, "watch", "src", "Main.elm"]))

    {:ok, _} = Ide.Debugger.start_session(slug)

    {:ok, after_phone} =
      Ide.Debugger.reload(slug, %{
        rel_path: "phone/src/CompanionApp.elm",
        source_root: "phone",
        source: phone_source,
        reason: "phone"
      })

    phone_only_ei = get_in(after_phone, [:companion, :shell, "debugger_contract"]) || %{}

    assert Enum.any?(Map.get(phone_only_ei, "subscription_calls", []), fn row ->
             Map.get(row, "target") == "GeneratedPreferences.onConfiguration"
           end)

    {:ok, after_watch} =
      Ide.Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source_root: "watch",
        source: watch_source,
        reason: "watch"
      })

    companion_ei = get_in(after_watch, [:companion, :shell, "debugger_contract"]) || %{}
    phone_ei = get_in(after_watch, [:phone, :shell, "debugger_contract"]) || %{}

    bridge_ctx = %{
      introspect: fn state, target ->
        case target do
          :companion -> get_in(state, [:companion, :shell, "debugger_contract"])
          :phone -> get_in(state, [:phone, :shell, "debugger_contract"])
          _ -> %{}
        end
      end,
      cmd_calls: &Ide.Debugger.IntrospectAccess.cmd_calls/2
    }

    contract = CompanionBridge.configuration_contract()

    subscription_calls = Map.get(companion_ei, "subscription_calls", [])

    companion_cb =
      CompanionBridgeRuntime.subscription_callback(companion_ei, contract, bridge_ctx)

    phone_cb =
      CompanionBridgeRuntime.subscription_callback(phone_ei, contract, bridge_ctx)

    callback = ConfigurationSave.subscription_callback(after_watch, bridge_ctx)

    matches =
      Enum.map(subscription_calls, fn row ->
        {Map.get(row, "target"), Map.get(row, "callback_constructor"),
         Ide.Debugger.CmdCall.subscription_call_matches?(row, contract.target_suffixes)}
      end)

    assert length(subscription_calls) > 0

    assert Enum.any?(matches, fn
             {"GeneratedPreferences.onConfiguration", "FromConfiguration", true} -> true
             _ -> false
           end),
           "unexpected subscription_calls: #{inspect(matches)}"

    assert companion_cb == "FromConfiguration"
    assert phone_cb == nil
    assert callback == "FromConfiguration"

    assert Enum.any?(Map.get(phone_only_ei, "subscription_calls", []), fn row ->
             Map.get(row, "target") == "GeneratedPreferences.onConfiguration"
           end)

    assert Enum.any?(subscription_calls, fn row ->
             Map.get(row, "target") == "GeneratedPreferences.onConfiguration"
           end)

    refute Enum.any?(subscription_calls, fn row ->
             Map.get(row, "target") == "Events.onMinuteChange"
           end)
  end
end
