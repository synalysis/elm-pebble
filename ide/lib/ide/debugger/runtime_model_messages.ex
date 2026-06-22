defmodule Ide.Debugger.RuntimeModelMessages do
  @moduledoc false

  alias Ide.Debugger.Types

  @spec wire_constructor(Types.wire_input()) :: String.t() | nil
  def wire_constructor(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
  end

  def wire_constructor(_message), do: nil

  @spec update_branch_matches_message?(String.t(), String.t()) :: boolean()
  def update_branch_matches_message?(branch, message)
      when is_binary(branch) and branch != "" and is_binary(message) and message != "" do
    branch == message or
      branch == wire_constructor(message) or
      branch_tokens_match_message?(branch, message)
  end

  def update_branch_matches_message?(_branch, _message), do: false

  defp branch_tokens_match_message?(branch, message) when is_binary(branch) and is_binary(message) do
    normalized =
      message
      |> String.replace(~r/[()]/, " ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    branch
    |> String.split(" ", trim: true)
    |> Enum.reject(&(&1 == "_"))
    |> Enum.all?(fn token -> String.contains?(normalized, token) end)
  end
end
