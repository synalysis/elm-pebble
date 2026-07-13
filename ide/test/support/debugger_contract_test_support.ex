defmodule Ide.Debugger.ContractTestSupport do
  @moduledoc false

  alias ElmEx.DebuggerContract.Types, as: ContractTypes
  alias Ide.Debugger.CompileContract

  @spec analyze_contract!(String.t(), String.t()) :: ContractTypes.introspect_payload()
  def analyze_contract!(source, path \\ "Main.elm") when is_binary(source) and is_binary(path) do
    {:ok, %{"debugger_contract" => contract}} = CompileContract.analyze_source(source, path)
    contract
  end

  @spec legacy_snapshot(String.t(), String.t()) :: {:ok, ContractTypes.introspect_snapshot()}
  def legacy_snapshot(source, path \\ "Main.elm") when is_binary(source) and is_binary(path) do
    contract = analyze_contract!(source, path)
    {:ok, %{"debugger_contract" => contract, "elm_introspect" => contract}}
  end

  @spec shell_contract(ContractTypes.introspect_payload()) :: ContractTypes.introspect_snapshot()
  def shell_contract(contract) when is_map(contract) do
    %{"debugger_contract" => contract}
  end
end
