defmodule Ide.DebuggerIntegrationCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using _opts do
    quote do
      use ExUnit.Case, async: false

      alias Ide.Debugger
      alias Ide.Debugger.AppMessageQueue
      alias Ide.Debugger.RuntimeExecutor
      alias Ide.Test.TimelineAssertions

      import Ide.DebuggerIntegrationHelpers

      alias Ide.Debugger.AgentStore

      @moduletag :integration
      @moduletag :slow
      @moduletag timeout: 180_000

      setup _tags do
        :ok = AgentStore.ensure_started(Ide.Debugger)
        :ok
      end
    end
  end
end
