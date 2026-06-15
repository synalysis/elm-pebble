defmodule Ide.Debugger.Types.PackageCmdErrorEventPayload do
  @moduledoc """
  Payload for `debugger.package_cmd_error` when package command execution fails.
  """

  alias Ide.Debugger.Types

  @type command_map :: Types.cmd_call()

  @type t :: %{
          optional(:target) => String.t(),
          optional(:package) => String.t(),
          optional(:command) => command_map(),
          optional(:error) => String.t(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | Types.wire_map()

  @spec from_error(String.t(), String.t(), command_map(), Types.execution_fallback_reason()) ::
          t()
  def from_error(target, package, command, reason)
      when is_binary(target) and is_binary(package) and is_map(command) do
    %{
      target: target,
      package: package,
      command: command,
      error: inspect(reason)
    }
  end
end
