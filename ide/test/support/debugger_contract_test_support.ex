defmodule Ide.Debugger.ContractTestSupport do
  @moduledoc false

  alias Ide.Debugger.CompileContract

  @spec analyze_contract!(String.t(), String.t()) :: map()
  def analyze_contract!(source, path \\ "Main.elm") when is_binary(source) and is_binary(path) do
    {:ok, %{"debugger_contract" => contract}} = CompileContract.analyze_source(source, path)
    contract
  end

  @spec legacy_snapshot(String.t(), String.t()) :: {:ok, map()}
  def legacy_snapshot(source, path \\ "Main.elm") when is_binary(source) and is_binary(path) do
    contract = analyze_contract!(source, path)
    {:ok, %{"debugger_contract" => contract, "elm_introspect" => contract}}
  end

  @spec shell_contract(map()) :: map()
  def shell_contract(contract) when is_map(contract) do
    %{"debugger_contract" => contract}
  end
end
