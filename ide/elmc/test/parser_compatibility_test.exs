defmodule Elmc.ParserCompatibilityTest do
  use ExUnit.Case

  alias ElmEx.Frontend.GeneratedParserBackend
  alias ElmEx.Frontend.CompatParserBackend

  test "compat and generated backends produce equivalent module AST on fixtures" do
    fixture_root = Path.expand("fixtures/simple_project/src", __DIR__)
    module_paths = Path.wildcard(Path.join(fixture_root, "**/*.elm"))

    assert module_paths != []

    Enum.each(module_paths, fn path ->
      assert {:ok, compat} = CompatParserBackend.parse_file(path)
      assert {:ok, generated} = GeneratedParserBackend.parse_file(path)
      assert normalize(compat) == normalize(generated)
    end)
  end

  defp normalize(value) when is_struct(value) do
    value |> Map.from_struct() |> normalize()
  end

  defp normalize(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {k, normalize(v)} end)
    |> Enum.sort()
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value), do: value
end
