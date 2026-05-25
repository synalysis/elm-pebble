defmodule Ide.Debugger.RuntimeExecutor.Types.RuntimeMode do
  @moduledoc """
  `Ide.Debugger.RuntimeExecutor` execution policy (`Application.get_env(:ide, RuntimeExecutor)[:runtime_mode]`).
  """

  @type t :: :legacy | :hybrid | :runtime_first

  @type wire :: String.t()
end
