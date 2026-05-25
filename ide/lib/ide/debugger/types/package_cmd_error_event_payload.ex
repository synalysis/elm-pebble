defmodule Ide.Debugger.Types.PackageCmdErrorEventPayload do
  @moduledoc """
  Payload for `debugger.package_cmd_error` when package command execution fails.
  """

  alias Ide.Debugger.Types

  @type command_map :: Types.cmd_call() | map()

  @type t :: %{
          optional(:target) => String.t(),
          optional(:package) => String.t(),
          optional(:command) => command_map(),
          optional(:error) => String.t(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type wire_map :: t() | map()

  @spec from_error(String.t(), String.t(), command_map(), term()) :: t()
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
