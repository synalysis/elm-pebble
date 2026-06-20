defmodule Ide.Debugger.CompiledElixirDeviceFollowupsTest do
  use Ide.DataCase, async: false

  @moduletag :debugger_session

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
  test "tangram inject_trigger applies CurrentDateTime after each manual MinuteChanged" do
    alias Ide.Debugger
    alias Ide.Projects

    slug = "elmx-inject-minute-followup-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ElmxInjectMinuteFollowup",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.set_simulator_settings(slug, %{
               "use_simulated_time" => true,
               "simulated_date" => "2026-06-20",
               "simulated_time" => "12:39:00",
               "timezone_offset_min" => 120
             })

    assert {:ok, stepped} =
             Debugger.step(slug, %{target: "watch", message: "MinuteChanged 40", count: 1})

    step_rows =
      stepped
      |> DebuggerSupport.debugger_rows(500)
      |> Enum.filter(fn row -> row.target == "watch" and row.type == "update" end)
      |> Enum.map(fn row -> {row.message, row.message_source} end)

    assert Enum.any?(step_rows, fn {msg, _} -> String.contains?(msg || "", "CurrentDateTime") end),
           "step baseline missing CurrentDateTime: #{inspect(step_rows)}"

    assert {:ok, state40} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "on_minute_change",
               message: "MinuteChanged 41"
             })

    rows41 =
      state40
      |> DebuggerSupport.debugger_rows(500)
      |> Enum.filter(fn row -> row.target == "watch" and row.type == "update" end)
      |> Enum.map(fn row -> {row.message, row.message_source} end)

    assert Enum.any?(rows41, fn {msg, _} -> String.contains?(msg || "", "MinuteChanged") end)

    assert Enum.any?(rows41, fn {msg, _} ->
             String.contains?(msg || "", "CurrentDateTime") and
               String.contains?(msg || "", "\"minute\":41")
           end),
           "expected CurrentDateTime follow-up for minute 41, got: #{inspect(rows41)}"

    assert {:ok, state41} =
             Debugger.inject_trigger(slug, %{
               target: "watch",
               trigger: "on_minute_change",
               message: "MinuteChanged",
               message_value: 42
             })

    rows42 =
      state41
      |> DebuggerSupport.debugger_rows(500)
      |> Enum.filter(fn row -> row.target == "watch" and row.type == "update" end)
      |> Enum.take(4)
      |> Enum.map(fn row -> {row.message, row.message_source} end)

    assert Enum.any?(rows42, fn {msg, source} ->
             source == "device_data" and String.contains?(msg || "", "CurrentDateTime") and
               String.contains?(msg || "", "\"minute\":42")
           end),
           "expected CurrentDateTime follow-up for message_value minute 42, got: #{inspect(rows42)}"
  end

  @tag timeout: 180_000
  test "watchface-poke-battle init device followups execute without clause errors" do
    assert "watchface-poke-battle" in DebuggerTemplateCorpus.template_keys()

    slug = "poke-followups-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, %{project: project}} =
             DebuggerTemplateCorpus.bootstrap_template("watchface-poke-battle",
               slug: slug,
               cleanup: false
             )

    try do
      workspace = project |> Ide.Projects.project_workspace_path() |> Path.join("watch")
      revision = slug <> "-rev"

      assert {:ok, %{elmx_manifest: manifest, elmx_revision: ^revision}} =
               Ide.Compiler.build_elmx_artifacts_in_memory(workspace,
                 revision: revision,
                 strip_dead_code: true
               )

      launch_context = Corpus.corpus_launch_context_for("basalt")

      init_request = %{
        elmx_manifest: manifest,
        elmx_revision: revision,
        current_model: %{"launch_context" => launch_context},
        message: nil,
        introspect: %{},
        source: "",
        source_root: "watch",
        rel_path: "src/Main.elm",
        current_view_tree: %{}
      }

      assert {:ok, init_payload} = Ide.Debugger.RuntimeExecutor.execute(init_request)

      init_model = get_in(init_payload.model_patch, ["runtime_model"]) || %{}
      assert get_in(init_model, ["scene", "ctor"]) == "Waiting"

      followups = init_payload[:followup_messages] || []

      {final_model, view_tree} =
        Enum.reduce(followups, {init_model, nil}, fn row, {runtime_model, _view} ->
          step_request =
            Map.merge(init_request, %{
              current_model: %{
                "launch_context" => launch_context,
                "runtime_model" => runtime_model
              },
              message: Map.get(row, "message"),
              message_value: Map.get(row, "message_value")
            })

          assert {:ok, step_payload} =
                   Ide.Debugger.RuntimeExecutor.execute(step_request),
                 "followup #{inspect(Map.get(row, "message"))} failed"

          next_model =
            get_in(step_payload.model_patch, ["runtime_model"])
            |> then(&Map.merge(runtime_model, &1 || %{}))

          {next_model, step_payload[:view_tree] || step_payload["view_tree"]}
        end)

      assert get_in(final_model, ["use24Hour"]) == true

      assert get_in(final_model, ["batteryLevel", "ctor"]) == "Just" and
               get_in(final_model, ["batteryLevel", "args", Access.at(0)]) == 88

      assert get_in(final_model, ["now", "ctor"]) == "Just"
      assert is_map(get_in(final_model, ["now", "args", Access.at(0)]))
      refute is_nil(view_tree)
    after
      _ = Ide.Projects.delete_project(project)
    end
  end

  @tag timeout: 180_000
  test "watchface-poke-battle Debugger.reload attaches elmx and applies init device followups" do
    alias Ide.Debugger
    alias Ide.Projects
    alias IdeWeb.WorkspaceLive.DebuggerSupport

    slug = "poke-reload-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "PokeReload",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-poke-battle"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    workspace = Projects.project_workspace_path(project) |> Path.join("watch")
    main_src = File.read!(Path.join(workspace, "src/Main.elm"))

    assert {:ok, _} = Debugger.start_session(slug)

    assert {:ok, _} =
             Debugger.set_watch_profile(slug, %{"watch_profile_id" => "aplite"})

    assert {:ok, state} =
             Debugger.reload(slug, %{
               rel_path: "src/Main.elm",
               source: main_src,
               reason: "test_poke_reload",
               source_root: "watch"
             })

    runtime_model = get_in(state, [:watch, :model, "runtime_model"]) || %{}
    assert get_in(runtime_model, ["scene", "ctor"]) == "Waiting"

    refute Enum.any?(state.debugger_timeline || [], fn row ->
             row.target == "watch" and row.type == "runtime_exec_error"
           end)

    assert get_in(runtime_model, ["use24Hour"]) == true
    assert get_in(runtime_model, ["batteryLevel", "ctor"]) == "Just"
    assert get_in(runtime_model, ["now", "ctor"]) == "Just"

    rows = DebuggerSupport.debugger_rows(state, 50) |> Enum.filter(&(&1.target == "watch"))

    refute Enum.any?(rows, fn row ->
             get_in(row, [:view_tree, "type"]) == "previewUnavailable" or
               get_in(row, [:preview, "type"]) == "previewUnavailable"
           end)

    watch_surface = Map.get(state, :watch) || %{}

    rendered =
      IdeWeb.WorkspaceLive.DebuggerSupport.rendered_tree(%{
        model: Map.get(watch_surface, :model) || Map.get(watch_surface, "model") || %{},
        view_tree: Map.get(watch_surface, :view_tree) || Map.get(watch_surface, "view_tree") || %{},
        shell: Map.get(watch_surface, :shell) || Map.get(watch_surface, "shell") || %{}
      })

    assert rendered["type"] == "windowStack"

    assert rendered_tree_contains_type?(rendered, "bitmapInRect") or
             rendered_tree_contains_type?(rendered, "drawBitmapInRect")

    refute rendered_tree_contains_type?(rendered, "previewUnavailable")
  end

  defp rendered_tree_contains_type?(%{"type" => type} = node, wanted) when is_binary(wanted) do
    type == wanted or
      Enum.any?(Map.get(node, "children") || [], &rendered_tree_contains_type?(&1, wanted))
  end

  defp rendered_tree_contains_type?(_node, _wanted), do: false

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
    alias Ide.Projects

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "ElmxCatalog",
               "slug" => "elmx-catalog-#{System.unique_integer([:positive])}",
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    phone_workspace = project |> Projects.project_workspace_path() |> Path.join("phone")
    json = ~s({"page1-0": {"wholeAnnotation": "chair"}})
    revision = "catalog-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, _manifest, runtime_model} =
             Corpus.corpus_phone_step_execute!(
               phone_workspace,
               "CatalogReceived",
               revision: revision,
               message_value: %{"ctor" => "Ok", "args" => [json]}
             )

    names = Map.get(runtime_model, "names") || []
    assert names != []
    assert Enum.any?(names, &is_binary/1)
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
