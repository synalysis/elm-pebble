defmodule ElmEx.Frontend.ModuleContractBuilder do
  @moduledoc """
  Compatibility wrapper for the legacy contract builder module name.
  """

  alias ElmEx.Frontend.GeneratedContractBuilder

  @spec build(String.t(), String.t(), String.t(), [String.t()]) :: ElmEx.Frontend.Module.t()
  def build(path, source, module_name, imports) do
    GeneratedContractBuilder.build(path, source, module_name, imports)
  end
end
