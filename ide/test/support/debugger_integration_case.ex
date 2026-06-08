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

      @moduletag :integration
      @moduletag :slow
    end
  end
end
