defmodule Ide.Mcp.CompiledElixirPhoneCompileTest do
  @moduledoc false

  use Ide.DataCase, async: false

  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus
  alias Ide.Mcp.DebuggerTemplateCorpus
  alias Ide.Projects

  @enabled? Corpus.corpus_enabled?()

  @phone_templates [
    "watchface-yes",
    "watchface-tangram-time",
    "watchface-weather-animated",
    "watchface-tutorial-complete",
    "companion-demo-phone-status",
    "companion-demo-storage",
    "companion-demo-weather-env",
    "companion-demo-calendar",
    "companion-demo-settings",
    "companion-demo-geolocation",
    "companion-demo-websocket",
    "companion-demo-timeline"
  ]

  for template_key <- @phone_templates do
    @tag :compiled_elixir_corpus
    @tag timeout: 180_000
    test "#{template_key} phone surface compiles with elmx when enabled" do
      if @enabled? and unquote(template_key) in DebuggerTemplateCorpus.template_keys() do
        assert_phone_compiles!(unquote(template_key), unquote("corpus-phone-#{template_key}-"))
      else
        assert true
      end
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-storage phone init executes default model when enabled" do
    if @enabled? and "companion-demo-storage" in DebuggerTemplateCorpus.template_keys() do
      assert_phone_init!("companion-demo-storage", "corpus-storage-phone-init-", fn model ->
        assert model["theme"]["ctor"] == "Dark"
        assert model["units"]["ctor"] == "Metric"
      end)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-phone-status phone init executes empty model when enabled" do
    if @enabled? and "companion-demo-phone-status" in DebuggerTemplateCorpus.template_keys() do
      assert_phone_init!("companion-demo-phone-status", "corpus-phone-init-", fn model ->
        assert model["batteryPercent"] == 0
        assert model["locale"] == "--"
      end)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-weather-env phone init executes empty model when enabled" do
    if @enabled? and "companion-demo-weather-env" in DebuggerTemplateCorpus.template_keys() do
      assert_phone_init!("companion-demo-weather-env", "corpus-weather-phone-init-", fn model ->
        assert model["temperatureC"] == 0
        assert model["condition"]["ctor"] == "UnknownWeather"
        assert model["sunriseMin"] == 0
      end)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-calendar phone init executes empty model when enabled" do
    if @enabled? and "companion-demo-calendar" in DebuggerTemplateCorpus.template_keys() do
      assert_phone_init!("companion-demo-calendar", "corpus-calendar-phone-init-", fn model ->
        assert model["lastTitle"] == ""
      end)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-settings phone init executes default model when enabled" do
    if @enabled? and "companion-demo-settings" in DebuggerTemplateCorpus.template_keys() do
      assert_phone_init!("companion-demo-settings", "corpus-settings-phone-init-", fn model ->
        assert model["ready"] == false
        assert model["configOutcome"]["ctor"] == "Nothing"
      end)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-geolocation phone init executes empty model when enabled" do
    if @enabled? and "companion-demo-geolocation" in DebuggerTemplateCorpus.template_keys() do
      assert_phone_init!("companion-demo-geolocation", "corpus-geo-phone-init-", fn model ->
        assert model["latitudeE6"] == 0
        assert model["longitudeE6"] == 0
      end)
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-websocket phone init executes default model when enabled" do
    if @enabled? and "companion-demo-websocket" in DebuggerTemplateCorpus.template_keys() do
      assert_phone_init!(
        "companion-demo-websocket",
        "corpus-ws-phone-init-",
        fn model ->
          assert model["status"]["ctor"] == "Open"
          assert model["statusDetail"] == "connected"
        end,
        apply_companion_bridge_followups: true
      )
    else
      assert true
    end
  end

  @tag :compiled_elixir_corpus
  @tag timeout: 180_000
  test "companion-demo-timeline phone init executes default model when enabled" do
    if @enabled? and "companion-demo-timeline" in DebuggerTemplateCorpus.template_keys() do
      assert_phone_init!(
        "companion-demo-timeline",
        "corpus-timeline-phone-init-",
        fn model ->
          assert model["token"] == "demo-timeline-token"
        end,
        apply_companion_bridge_followups: true
      )
    else
      assert true
    end
  end

  defp assert_phone_compiles!(template_key, revision_prefix) when is_binary(template_key) do
    assert {:ok, %{project: project}} =
             DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

    try do
      phone_workspace = project |> Projects.project_workspace_path() |> Path.join("phone")
      revision = revision_prefix <> Integer.to_string(:erlang.unique_integer([:positive]))

      case Elmx.compile_in_memory(phone_workspace, %{
             entry_module: "CompanionApp",
             revision: revision,
             mode: :ide_runtime,
             strip_dead_code: true
           }) do
        {:ok, %Elmx.CompileResult{}} ->
          assert Elmx.module_for_revision(revision)

        {:error, reason} when reason == :missing_elm_json ->
          flunk("phone workspace missing elm.json")

        {:error, reason} ->
          Corpus.refute_compile_gap!(reason)
      end
    after
      _ = Projects.delete_project(project)
    end
  end

  defp assert_phone_init!(template_key, revision_prefix, assert_model, opts \\ [])
       when is_binary(template_key) and is_function(assert_model, 1) do
    Corpus.ensure_compiled_elixir_backend!()

    assert {:ok, %{project: project}} =
             DebuggerTemplateCorpus.bootstrap_template(template_key, cleanup: false)

    try do
      phone_workspace = project |> Projects.project_workspace_path() |> Path.join("phone")

      case Corpus.corpus_phone_init_execute!(
             phone_workspace,
             Keyword.merge(opts,
               revision: revision_prefix <> Integer.to_string(:erlang.unique_integer([:positive]))
             )
           ) do
        {:ok, _manifest, runtime_model} ->
          assert_model.(runtime_model)

        {:compile_error, reason} ->
          Corpus.refute_compile_gap!(reason)
      end
    after
      _ = Projects.delete_project(project)
    end
  end
end
