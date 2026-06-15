defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Export do
  @moduledoc false
  @dialyzer :no_match

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Export.{AgentState, Contract}
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type debugger_state_export_ctx :: Types.debugger_state_export_ctx()
  @type runtime_input :: Types.runtime_input()

  defdelegate copy_json(term), to: AgentState
  defdelegate debugger_agent_state_markdown(ctx), to: AgentState
  defdelegate format_debugger_contract_brief(runtime), to: Contract
  defdelegate format_elm_introspect_brief(runtime), to: Contract
end
