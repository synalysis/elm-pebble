defmodule Ide.Debugger.Types.PackageCmdEventPayload do
  @moduledoc """
  Payload for `debugger.package_cmd` runtime follow-up events.
  """

  alias Ide.Debugger.Types

  @type command_map :: Types.cmd_call()

  @type t :: %{
          optional(:target) => String.t(),
          optional(:package) => String.t(),
          optional(:command) => command_map(),
          optional(:response_message) => String.t() | nil,
          optional(:response) => Types.subscription_payload(),
          optional(:simulated) => boolean(),
          optional(:detail) => String.t(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @type wire_map :: t() | Types.wire_map()

  @spec from_http(
          String.t(),
          String.t(),
          String.t(),
          command_map(),
          Types.subscription_payload(),
          boolean(),
          String.t() | nil
        ) :: t()
  def from_http(target, package, response_message, command, response, simulated, followup_message)
      when is_binary(target) and is_binary(package) and is_map(command) do
    %{
      target: target,
      package: package,
      response_message: response_message || followup_message || "elm/http",
      command: command,
      response: response,
      simulated: simulated
    }
  end

  @spec from_followup(String.t(), String.t(), String.t() | nil) :: t()
  def from_followup(target, package, response_message)
      when is_binary(target) and is_binary(package) do
    %{
      target: target,
      package: package,
      response_message: response_message
    }
  end

  @spec from_handler(wire_map()) :: t()
  def from_handler(%{} = payload), do: Map.take(payload, payload_keys())

  defp payload_keys do
    [:target, :package, :command, :response_message, :response, :simulated, :detail]
  end
end
