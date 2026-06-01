defmodule ElmEx.EffectsFromCoreIRTest do
  use ExUnit.Case, async: true

  alias ElmEx.CoreIR
  alias ElmEx.DebuggerContract
  alias ElmEx.DebuggerContract.EffectsFromCoreIR
  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

  @subs_source """
  module Main exposing (..)

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

  test "effect_fields from Core IR matches project contract subscriptions" do
    tmpdir =
      Path.join(
        System.tmp_dir!(),
        "effects_core_ir_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(tmpdir) end)

    File.mkdir_p!(Path.join(tmpdir, "src"))

    File.write!(
      Path.join(tmpdir, "elm.json"),
      Jason.encode!(%{"type" => "application", "source-directories" => ["src"]})
    )

    File.write!(Path.join(tmpdir, "src/Main.elm"), @subs_source)

    assert {:ok, project} = Bridge.load_project(tmpdir)
    assert {:ok, ir} = Lowerer.lower_project(project)
    assert {:ok, core_ir} = CoreIR.from_ir(ir, strict?: false)

    assert {:ok, project_snapshot} = DebuggerContract.from_project(project)
    project_contract = DebuggerContract.contract_payload(project_snapshot)

    core_effects = EffectsFromCoreIR.effect_fields(core_ir, "Main")

    assert project_contract["subscription_calls"] == core_effects["subscription_calls"]
  end
end
