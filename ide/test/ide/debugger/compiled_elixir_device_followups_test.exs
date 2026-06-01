defmodule Ide.Debugger.CompiledElixirDeviceFollowupsTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus
  alias Ide.Mcp.DebuggerTemplateCorpus
  alias IdeWeb.WorkspaceLive.DebuggerSupport

  setup do
    old = Application.get_env(:ide, Ide.Debugger.RuntimeExecutor, [])

    on_exit(fn ->
      Application.put_env(:ide, Ide.Debugger.RuntimeExecutor, old)
    end)

    Corpus.ensure_compiled_elixir_backend!()
    :ok
  end

  @tag timeout: 180_000
  test "watchface-tangram-time MinuteChanged returns device followup for CurrentDateTime" do
    assert "watchface-tangram-time" in DebuggerTemplateCorpus.template_keys()

    assert {:ok, %{project: project}} =
             DebuggerTemplateCorpus.bootstrap_template("watchface-tangram-time", cleanup: false)

    try do
      workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")
      revision = "tangram-minute-" <> Integer.to_string(:erlang.unique_integer([:positive]))

      assert {:ok, manifest, init_model} =
               Corpus.corpus_compile_and_execute_init!(workspace,
                 revision: revision,
                 watch_profile_id: "emery"
               )

      launch_context = Corpus.corpus_launch_context_for("emery")

      assert {:ok, step_payload} =
               Ide.Debugger.RuntimeExecutor.execute(%{
                 elmx_manifest: manifest,
                 elmx_revision: revision,
                 current_model: %{
                   "launch_context" => launch_context,
                   "runtime_model" => init_model
                 },
                 message: "MinuteChanged 46",
                 introspect: %{},
                 source: "",
                 source_root: "watch",
                 rel_path: "src/Main.elm",
                 current_view_tree: %{}
               })

      followups = step_payload[:followup_messages] || []

      assert Enum.any?(followups, fn row ->
               Map.get(row, "message") == "CurrentDateTime" and
                 String.starts_with?(get_in(row, ["command", "kind"]) || "", "cmd.device.")
             end)
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  @tag timeout: 180_000
  test "tangram Debugger.step applies CurrentDateTime after MinuteChanged on compiled_elixir" do
    alias Ide.Debugger
    alias Ide.Projects
    alias IdeWeb.WorkspaceLive.DebuggerSupport

    slug = "elmx-minute-followup-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ElmxMinuteFollowup",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.set_simulator_settings(slug, %{
               "use_simulated_time" => true,
               "simulated_date" => "2026-06-01",
               "simulated_time" => "15:44:00",
               "timezone_offset_min" => 120
             })

    assert {:ok, state} =
             Debugger.step(slug, %{target: "watch", message: "MinuteChanged 46", count: 1})

    rows =
      state
      |> DebuggerSupport.debugger_rows(500)
      |> Enum.filter(fn row -> row.target == "watch" and row.type == "update" end)

    assert Enum.any?(rows, &String.contains?(&1.message || "", "MinuteChanged"))

    assert Enum.any?(rows, &String.contains?(&1.message || "", "CurrentDateTime")),
           "expected CurrentDateTime device follow-up row, got: #{inspect(Enum.map(rows, & &1.message))}"
  end

  @tag timeout: 180_000
  test "watchface-analog init returns non-empty runtime_model on compiled_elixir" do
    assert "watchface-analog" in DebuggerTemplateCorpus.template_keys()

    assert {:ok, %{project: project}} =
             DebuggerTemplateCorpus.bootstrap_template("watchface-analog", cleanup: false)

    try do
      workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")
      revision = "analog-init-" <> Integer.to_string(:erlang.unique_integer([:positive]))

      assert {:ok, _manifest, init_model} =
               Corpus.corpus_compile_and_execute_init!(workspace,
                 revision: revision,
                 watch_profile_id: "emery"
               )

      refute init_model == %{}

      assert is_map(Map.get(init_model, "launch_context")) or
               map_size(Map.drop(init_model, ["launch_context"])) > 0
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  @tag timeout: 180_000
  test "tangram companion CatalogReceived Ok applies on compiled_elixir http follow-up" do
    alias Ide.Debugger
    alias Ide.Projects

    slug = "elmx-catalog-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ElmxCatalog",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, _} = Debugger.start_session(slug)

    phone_src =
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

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source: phone_src,
               reason: "test_catalog",
               source_root: "phone"
             })

    json = ~s({"page1-0": {"wholeAnnotation": "chair"}})

    assert {:ok, state} =
             Debugger.step(slug, %{
               target: "companion",
               message: "CatalogReceived",
               message_value: %{"ctor" => "Ok", "args" => [json]},
               count: 1
             })

    refute Enum.any?(state.debugger_timeline, fn row ->
             row.target == "companion" and row.type == "runtime_exec_error" and
               String.contains?(row.message || "", "CatalogReceived")
           end)

    names =
      get_in(state, [:companion, :model, "runtime_model", "names"]) ||
        get_in(state, [:phone, :model, "runtime_model", "names"]) || []

    assert names != []
  end

  @tag timeout: 180_000
  test "tangram bootstrap leaves non-empty companion runtime_model on compiled_elixir" do
    alias Ide.Debugger
    alias Ide.Projects

    slug = "elmx-companion-model-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ElmxCompanionModel",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.reload(slug, %{
               rel_path: "src/CompanionApp.elm",
               source:
                 File.read!(
                   Path.join([
                     "priv",
                     "project_templates",
                     "watchface_tangram_time",
                     "phone",
                     "src",
                     "CompanionApp.elm"
                   ])
                 ),
               reason: "test_companion_init",
               source_root: "phone"
             })

    assert {:ok, state} = Debugger.snapshot(slug)

    phone_runtime_model =
      get_in(state, [:companion, :model, "runtime_model"]) ||
        get_in(state, [:phone, :model, "runtime_model"]) || %{}

    refute phone_runtime_model == %{}

    assert Map.drop(phone_runtime_model, [
             "status",
             "protocol_message_count",
             "protocol_inbound_count",
             "protocol_outbound_count",
             "protocol_last_inbound_message",
             "protocol_last_inbound_from"
           ]) != %{},
           "expected CompanionApp fields on phone runtime_model, got: #{inspect(phone_runtime_model)}"
  end

end
