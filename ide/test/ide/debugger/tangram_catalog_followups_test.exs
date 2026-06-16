defmodule Ide.Debugger.TangramCatalogFollowupsTest do
  use Ide.DataCase, async: false

  alias Ide.Debugger.CompiledElixirCorpusHelpers, as: Corpus
  alias Ide.Debugger.RuntimeExecutor
  alias Ide.Projects

  setup do
    Corpus.ensure_compiled_elixir_backend!()
    :ok
  end

  @tag timeout: 180_000
  test "CatalogReceived Ok schedules SvgReceived http follow-up" do
    slug = "tangram-catalog-followups-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "TangramCatalogFollowups",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    phone_workspace = project |> Projects.project_workspace_path() |> Path.join("phone")
    revision = "catalog-followups-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, manifest, init_model} =
             Corpus.corpus_phone_init_execute!(phone_workspace, revision: revision)

    json = ~s({"page1-0": {"wholeAnnotation": "chair"}, "page1-105": {"wholeAnnotation": "bird"}})

    assert {:ok, payload} =
             RuntimeExecutor.execute(%{
               elmx_manifest: manifest,
               elmx_revision: revision,
               current_model: %{"runtime_model" => init_model},
               message: "CatalogReceived",
               message_value: %{"ctor" => "Ok", "args" => [json]},
               introspect: %{},
               source: "",
               source_root: "phone",
               rel_path: "src/CompanionApp.elm",
               current_view_tree: %{}
             })

    followups = payload[:followup_messages] || []

    assert Enum.any?(followups, fn row ->
             Map.get(row, "message") == "SvgReceived" and
               String.contains?(get_in(row, ["command", "url"]) || "", "tangrams-svg")
           end),
           "expected fetchFigure http follow-up after CatalogReceived, got: #{inspect(followups)}"
  end

  @tag timeout: 180_000
  test "SvgReceived Ok schedules figure geometry protocol commands" do
    slug = "tangram-svg-followups-#{System.unique_integer([:positive])}"

    assert {:ok, project} =
             Projects.create_project(%{
               "name" => "TangramSvgFollowups",
               "slug" => slug,
               "target_type" => "watchface",
               "template" => "watchface-tangram-time"
             })

    on_exit(fn -> Projects.delete_project(project) end)

    phone_workspace = project |> Projects.project_workspace_path() |> Path.join("phone")
    revision = "svg-followups-" <> Integer.to_string(:erlang.unique_integer([:positive]))

    assert {:ok, manifest, init_model} =
             Corpus.corpus_phone_init_execute!(phone_workspace, revision: revision)

    svg = ~s(
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 132 126">
        <polygon points="58,52 16,22 6,62" fill="#0055FF"/>
        <polygon points="74,52 108,22 118,62" fill="#00AAFF"/>
        <polygon points="48,60 66,46 84,60 66,76" fill="#55FFFF"/>
        <polygon points="84,54 102,46 98,66" fill="#00FFFF"/>
        <polygon points="48,66 26,58 20,74 42,82" fill="#001133"/>
        <polygon points="61,76 38,92 70,90" fill="#0055DD"/>
        <polygon points="72,76 100,90 78,94" fill="#AADDFF"/>
      </svg>
    )

    catalog_model =
      init_model
      |> Map.put("names", ["page1-0"])
      |> Map.put("figure", 0)

    assert {:ok, payload} =
             RuntimeExecutor.execute(%{
               elmx_manifest: manifest,
               elmx_revision: revision,
               current_model: %{"runtime_model" => catalog_model},
               message: "SvgReceived",
               message_value: %{"ctor" => "Ok", "args" => [svg]},
               introspect: %{},
               source: "",
               source_root: "phone",
               rel_path: "src/CompanionApp.elm",
               current_view_tree: %{}
             })

    protocol_events = payload[:protocol_events] || []

    assert Enum.any?(protocol_events, fn event ->
             payload = Map.get(event, :payload) || Map.get(event, "payload") || %{}

             event.type == "debugger.protocol_tx" and
               String.contains?(
                 to_string(Map.get(payload, :message) || Map.get(payload, "message") || ""),
                 "BeginFigure"
               )
           end)
  end
end
