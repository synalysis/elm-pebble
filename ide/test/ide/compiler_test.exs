defmodule Ide.CompilerTest do
  use ExUnit.Case, async: true

  alias Ide.Compiler

  test "normalizes valid manifest payload shape" do
    payload = %{
      "supported_packages" => ["elm/core"],
      "excluded_packages" => ["elm/html"],
      "modules_detected" => ["Main"]
    }

    {normalized, diagnostics} = Compiler.normalize_manifest_payload(payload)

    assert normalized.schema_version == 1
    assert normalized.supported_packages == ["elm/core"]
    assert normalized.excluded_packages == ["elm/html"]
    assert normalized.modules_detected == ["Main"]
    assert diagnostics == []
  end

  test "normalizes missing/invalid manifest fields with warnings" do
    payload = %{
      "supported_packages" => ["elm/core", 1],
      "excluded_packages" => "elm/html"
    }

    {normalized, diagnostics} = Compiler.normalize_manifest_payload(payload)

    assert normalized.supported_packages == ["elm/core"]
    assert normalized.excluded_packages == []
    assert normalized.modules_detected == []
    assert length(diagnostics) >= 2
    assert Enum.all?(diagnostics, &(&1.source == "elmc/manifest"))
  end
end
