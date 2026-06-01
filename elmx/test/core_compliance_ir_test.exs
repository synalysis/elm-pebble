defmodule Elmx.CoreComplianceIRTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer

  @project_dir Path.expand("fixtures/simple_project", __DIR__)

  test "CoreCompliance functions lower without :unsupported bodies" do
    {:ok, project} = Bridge.load_project(@project_dir)
    {:ok, ir} = Lowerer.lower_project(project)
    mod = Enum.find(ir.modules, &(&1.name == "CoreCompliance"))

    bad =
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.filter(fn decl ->
        Map.get(decl.expr, :op) == :unsupported or
          expr_contains?(decl.expr, :unsupported)
      end)
      |> Enum.map(& &1.name)

    assert bad == [],
           "expected all CoreCompliance functions to parse; still unsupported: #{inspect(bad)}"
  end

  defp expr_contains?(%{op: :unsupported}, :unsupported), do: true

  defp expr_contains?(map, op) when is_map(map) do
    Enum.any?(map, fn
      {_, v} when is_map(v) -> expr_contains?(v, op)
      {_, v} when is_list(v) -> Enum.any?(v, &expr_contains?(&1, op))
      _ -> false
    end)
  end

  defp expr_contains?(_, _), do: false
end
