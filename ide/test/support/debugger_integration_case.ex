defmodule Ide.DebuggerIntegrationCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using _opts do
    quote do
      use ExUnit.Case, async: false

      alias Ide.Debugger
      alias Ide.Debugger.AppMessageQueue
      alias Ide.Debugger.RuntimeExecutor
      alias Ide.Debugger.RuntimeExecutor.ElmcAdapter
      alias Ide.Test.TimelineAssertions

      import Ide.DebuggerIntegrationHelpers

      @moduletag :integration
    end
  end
end
