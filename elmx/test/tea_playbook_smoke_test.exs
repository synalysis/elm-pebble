defmodule Elmx.TeaPlaybookSmokeTest do
  @moduledoc """
  Runs shared `Elmx.TeaPlaybook` scenarios through the elmx Executor (debugger TEA path).

  Same playbooks drive elmc host smokes (`Elmc.TestSupport.TeaScenario`) so debugger
  and generated C stay aligned.
  """

  use ExUnit.Case, async: false

  alias Elmx.TeaPlaybook
  alias Elmx.TestSupport.{TeaPlaybookRunner, TemplateProject}

  @moduletag :slow
  @moduletag :tea_playbook

  @templates (
    default = TemplateProject.tea_playbook_template_dirs()

    case System.get_env("ELMC_HOST_SMOKE_TEMPLATE") || System.get_env("ELMX_TEA_PLAYBOOK_TEMPLATE") do
      nil ->
        default

      raw ->
        selected =
          raw
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Enum.filter(default, &(&1 in selected))
    end
  )

  for template <- @templates do
    @tag template: template

    test "TEA playbook elmx smoke: #{template}" do
      run_playbook!(unquote(template))
    end
  end

  defp run_playbook!(template) do
    playbook = TeaPlaybook.for_template(template)
    assert playbook.template == template

    # Round-trip JSON shape used by both backends / fixtures.
    assert TeaPlaybook.from_json_map(TeaPlaybook.to_json_map(playbook)).template == template

    {:ok, project_dir} = TemplateProject.scaffold_playbook_template(template)

    assert {:ok, %Elmx.CompileResult{entry_module: module}} =
             Elmx.compile_in_memory(project_dir, %{
               entry_module: "Main",
               revision: "tea-playbook-#{template}",
               mode: :ide_runtime,
               strip_dead_code: true
             })

    result = TeaPlaybookRunner.run!(playbook, module)
    TeaPlaybookRunner.assert_expects!(result)

    assert result.view_output != []
  end
end
