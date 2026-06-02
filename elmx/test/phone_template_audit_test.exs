defmodule Elmx.PhoneTemplateAuditTest do
  use ExUnit.Case, async: false

  alias Elmx.TestSupport.{CoverageGate, QualifiedCallAudit, TemplateProject}

  @tag :phone_template_audit
  @tag timeout: 180_000
  test "companion phone templates compile without stdlib qualified_call fallbacks" do
    for template_key <- TemplateProject.representative_phone_template_keys() do
      {:ok, phone_dir} = TemplateProject.scaffold_phone(template_key)
      revision = "phone-audit-#{template_key}-#{System.unique_integer([:positive])}"

      try do
        assert {:ok, result} =
                 Elmx.compile_in_memory(phone_dir, %{
                   entry_module: "CompanionApp",
                   revision: revision,
                   strip_dead_code: true,
                   mode: :ide_runtime
                 })

        assert QualifiedCallAudit.scan_compile_result(result) == []
      after
        File.rm_rf(phone_dir)
      end
    end
  end

  @tag :phone_template_audit
  test "companion phone templates have no unsupported IR ops after lowering" do
    for template_key <- TemplateProject.representative_phone_template_keys() do
      {:ok, phone_dir} = TemplateProject.scaffold_phone(template_key)

      try do
        CoverageGate.scan_project_ir!(phone_dir)
      after
        File.rm_rf(phone_dir)
      end
    end
  end
end
