defmodule Ide.Debugger.DeferredCompanionBootstrapTest do
  use Ide.DebuggerIntegrationCase, async: false

  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.BootstrapInit
  alias Ide.Debugger.DeferredCompanionInit
  alias IdeWeb.WorkspaceLive.DebuggerPage.ModelMetadata

  test "deferred companion init runs after fast bootstrap clears only skip-compile flag" do
    slug = "sim-deferred-companion-init-#{System.unique_integer([:positive])}"

    watch_source =
      File.read!(
        Path.join(["priv", "project_templates", "watchface_tangram_time", "src", "Main.elm"])
      )

    companion_source =
      File.read!(
        Path.join([
          "priv",
          "project_templates",
          "watchface_tangram_time",
          "phone",
          "src",
          "CompanionApp.elm"
        ])
      )

    {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: watch_source,
               reason: "watch",
               source_root: "watch"
             })

    assert {:ok, _} = AgentSession.mutate(slug, &BootstrapInit.with_companion_bootstrap_flags/1)

    try do
      assert {:ok, _} =
               Debugger.reload(slug, %{
                 rel_path: "src/CompanionApp.elm",
                 source: companion_source,
                 reason: "debugger_companion_bootstrap",
                 source_root: "phone"
               })
    after
      assert {:ok, _} = AgentSession.mutate(slug, &BootstrapInit.clear_companion_bootstrap_flags/1)
    end

    assert :ok = DeferredCompanionInit.run(slug)

    assert {:ok, snap} = Debugger.snapshot(slug, event_limit: 500)

    assert Enum.any?(snap.debugger_timeline || [], fn row ->
             row.target == "phone" and row.type == "init"
           end)

    watch_updates =
      (snap.debugger_timeline || [])
      |> Enum.filter(fn row -> row.target == "watch" and row.type == "update" end)

    assert Enum.any?(watch_updates, fn row ->
             is_binary(row.message) and String.contains?(row.message, "FromPhone")
           end)

    public_companion = ModelMetadata.public_model(Map.get(snap, :companion))
    assert Map.has_key?(public_companion, "figure")

    public_watch = ModelMetadata.public_model(Map.get(snap, :watch))
    assert %{"ctor" => "Just", "args" => [0]} = Map.get(public_watch, "companionFigure")
  end
end
