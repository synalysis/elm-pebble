defmodule Ide.Debugger.CompileContractTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.CompileContract
  alias Ide.Debugger.RuntimeArtifacts

  @subs_source """
  module Subs exposing (..)

  import Pebble.Events as Events

  type Msg
      = Tick

  subscriptions _ =
      Events.batch [ Events.onSecondChange Tick ]

  init _ =
      ( {}, Cmd.none )

  update _ m =
      m

  view _ =
      X.y []
  """

  test "analyze_source returns debugger_contract payload" do
    assert {:ok, %{"debugger_contract" => contract}} =
             CompileContract.analyze_source(@subs_source, "Subs.elm")

    assert contract["contract_version"] == CompileContract.version()
    assert Enum.any?(contract["subscription_calls"] || [], &is_map/1)
  end

  test "encode/decode round trip" do
    assert {:ok, %{"debugger_contract" => contract}} =
             CompileContract.analyze_source(@subs_source, "Subs.elm")

    assert CompileContract.decode(CompileContract.encode(contract))["contract_version"] ==
             CompileContract.version()
  end

  test "from_artifacts reads contract from compile fields" do
    contract = %{"msg_constructors" => ["Tick"], "contract_version" => CompileContract.version()}

    assert CompileContract.from_artifacts(%{
             "debugger_contract" => contract
           }) == contract

    assert CompileContract.from_artifacts(%{
             "debugger_contract_b64" => CompileContract.encode(contract)
           })["msg_constructors"] == ["Tick"]
  end

  test "entrypoint_path? matches watch Main and phone companion entry" do
    assert CompileContract.entrypoint_path?("watch", "src/Main.elm")
    assert CompileContract.entrypoint_path?("watch", "Main.elm")
    refute CompileContract.entrypoint_path?("watch", "src/Render.elm")
    assert CompileContract.entrypoint_path?("phone", "src/CompanionApp.elm")
    refute CompileContract.entrypoint_path?("phone", "src/Other.elm")
  end

  test "RuntimeArtifacts.introspect prefers debugger_contract on shell" do
    legacy = %{"msg_constructors" => ["Legacy"]}

    contract = %{
      "msg_constructors" => ["Contract"],
      "contract_version" => CompileContract.version()
    }

    shell = %{
      "debugger_contract" => contract,
      "elm_introspect" => legacy
    }

    assert RuntimeArtifacts.introspect(%{shell: shell, model: %{}}) == contract
  end
end
