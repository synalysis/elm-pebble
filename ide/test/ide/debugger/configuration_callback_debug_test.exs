defmodule Ide.Debugger.ConfigurationCallbackDebugTest do
  use Ide.DataCase, async: false

  @moduletag :integration
  @moduletag :slow
  @moduletag timeout: 180_000

  test "debug configuration callback resolution" do
    slug = "cfg-debug-#{System.unique_integer([:positive])}"

    {:ok, project} =
      Ide.Projects.create_project(%{
        "name" => "CfgDebug",
        "slug" => slug,
        "target_type" => "app",
        "template" => "watchface-yes"
      })

    root = Ide.Projects.project_workspace_path(project)
    phone_source = File.read!(Path.join([root, "phone", "src", "CompanionApp.elm"]))
    watch_source = File.read!(Path.join([root, "watch", "src", "Main.elm"]))

    {:ok, _} = Ide.Debugger.start_session(slug)

    {:ok, _} =
      Ide.Debugger.reload(slug, %{
        rel_path: "phone/src/CompanionApp.elm",
        source_root: "phone",
        source: phone_source,
        reason: "phone"
      })

    {:ok, after_watch} =
      Ide.Debugger.reload(slug, %{
        rel_path: "watch/src/Main.elm",
        source_root: "watch",
        source: watch_source,
        reason: "watch"
      })

    companion_ei = get_in(after_watch, [:companion, :shell, "debugger_contract"]) || %{}
    phone_ei = get_in(after_watch, [:phone, :shell, "debugger_contract"]) || %{}

    IO.puts("companion subscription_calls: #{length(Map.get(companion_ei, "subscription_calls", []))}")
    IO.puts("phone subscription_calls: #{length(Map.get(phone_ei, "subscription_calls", []))}")

    contract = Ide.Debugger.CompanionBridge.configuration_contract()
    ctx = %{cmd_calls: &Ide.Debugger.IntrospectAccess.cmd_calls/2}

    companion_cb =
      Ide.Debugger.CompanionBridge.Runtime.subscription_callback(companion_ei, contract, ctx)

    phone_cb =
      Ide.Debugger.CompanionBridge.Runtime.subscription_callback(phone_ei, contract, ctx)

    IO.inspect({companion_cb, phone_cb}, label: "callbacks")

    {:ok, state} = Ide.Debugger.save_configuration(slug, %{})

    config_rows =
      state.debugger_timeline
      |> Enum.filter(&(&1.message_source == "configuration"))
      |> Enum.map(&{&1.target, String.slice(&1.message || "", 0..30)})

    IO.inspect(config_rows, label: "config_rows")
    assert true
  end
end
