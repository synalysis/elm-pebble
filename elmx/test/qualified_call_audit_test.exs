defmodule Elmx.QualifiedCallAuditTest do
  use ExUnit.Case, async: false

  alias Elmx.TestSupport.{QualifiedCallAudit, TemplateProject}

  @tag :qualified_call_audit
  @tag timeout: 300_000
  test "representative templates compile without stdlib qualified_call fallbacks in generated code" do
    for template_key <- TemplateProject.representative_template_keys() do
      {:ok, project_dir} = TemplateProject.scaffold_template(template_key)

      entry_module =
        if File.exists?(Path.join(project_dir, "src/CompanionApp.elm")),
          do: "CompanionApp",
          else: "Main"

      revision = "audit-#{template_key}-#{System.unique_integer([:positive])}"

      try do
        assert {:ok, result} =
                 Elmx.compile_in_memory(project_dir, %{
                   entry_module: entry_module,
                   revision: revision,
                   strip_dead_code: true,
                   mode: :ide_runtime
                 })

        findings = QualifiedCallAudit.scan_compile_result(result)

        assert findings == [],
               """
               qualified_call audit findings for #{template_key}:
               #{Enum.map_join(findings, "\n", &"  L#{&1.line}: #{&1.excerpt}")}
               """
      after
        File.rm_rf(project_dir)
      end
    end
  end

  test "simple_project generated code has no stdlib qualified_call fallbacks" do
    revision = "audit-simple-#{System.unique_integer([:positive])}"

    assert {:ok, result} =
             Elmx.compile_in_memory(
               Path.expand("fixtures/simple_project", __DIR__),
               %{
                 entry_module: "Main",
                 revision: revision,
                 strip_dead_code: true,
                 mode: :ide_runtime
               }
             )

    assert QualifiedCallAudit.scan_compile_result(result) == []
  end
end
