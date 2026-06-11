defmodule Ide.Mcp.DebuggerTemplateCorpusTest do
  @moduledoc """
  Systematic debugger checks: one MCP bootstrap per project template.

  Set `UPDATE_DEBUGGER_TEMPLATE_SNAPSHOTS=1` to refresh golden fixtures under
  `test/fixtures/debugger_template_corpus/<template>.json`.
  """

  use Ide.DataCase, async: false

  alias Ide.Mcp.DebuggerTemplateCorpus

  @update_snapshots? System.get_env("UPDATE_DEBUGGER_TEMPLATE_SNAPSHOTS") in ["1", "true", "TRUE"]

  @tag :template_corpus
  @tag timeout: 120_000
  test "templates.list matches ProjectTemplates.template_keys" do
    alias Ide.Mcp.Tools

    assert {:ok, %{templates: listed}} = Tools.call("templates.list", %{}, [:read])
    listed_keys = Enum.map(listed, & &1.key) |> Enum.sort()

    assert listed_keys == DebuggerTemplateCorpus.template_keys() |> Enum.sort()
  end

  for template <- DebuggerTemplateCorpus.template_keys() do
    @tag :template_corpus
    @tag timeout: 120_000
    test "MCP debugger bootstrap snapshot for #{template}" do
      template = unquote(template)

      assert {:ok, %{snapshot: snapshot}} =
               DebuggerTemplateCorpus.run_template(template, cleanup: true)

      DebuggerTemplateCorpus.assert_contract!(snapshot, template)

      if @update_snapshots? do
        DebuggerTemplateCorpus.write_fixture!(template, snapshot)
        assert File.exists?(DebuggerTemplateCorpus.fixture_path(template))
      else
        case DebuggerTemplateCorpus.load_fixture(template) do
          {:ok, expected} ->
            assert :ok = DebuggerTemplateCorpus.compare_snapshots(snapshot, expected)

          {:error, :missing} ->
            flunk(
              "missing fixture #{DebuggerTemplateCorpus.fixture_path(template)}; " <>
                "run UPDATE_DEBUGGER_TEMPLATE_SNAPSHOTS=1 mix test test/ide/mcp/debugger_template_corpus_test.exs"
            )
        end
      end
    end
  end

  for template <- DebuggerTemplateCorpus.subscription_step_template_keys() do
    @tag :template_corpus_step
    @tag timeout: 120_000
    test "subscription step uses runtime execution for #{template}" do
      template = unquote(template)

      assert {:ok, %{slug: slug, project: project}} =
               DebuggerTemplateCorpus.bootstrap_template(template, cleanup: false)

      try do
        assert :ok = DebuggerTemplateCorpus.assert_subscription_steps_runtime!(slug, template)
      after
        _ = Ide.Projects.delete_project(project)
      end
    end
  end
end
