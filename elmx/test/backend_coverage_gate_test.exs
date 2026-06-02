defmodule Elmx.BackendCoverageGateTest do
  use ExUnit.Case

  alias Elmx.TestSupport.CoverageGate
  alias Elmx.TestSupport.TemplateProject

  @tag :representative_templates
  test "no unsupported backend ops in simple_project after lowering" do
    project_dir = Path.expand("fixtures/simple_project", __DIR__)
    CoverageGate.scan_project_ir!(project_dir)
  end

  @tag :representative_templates
  @tag timeout: 180_000
  test "no unsupported backend ops in representative IDE templates after lowering" do
    for template_key <- TemplateProject.representative_template_keys() do
      {:ok, project_dir} = TemplateProject.scaffold_template(template_key)

      try do
        CoverageGate.scan_project_ir!(project_dir)
      after
        File.rm_rf(project_dir)
      end
    end
  end
end
