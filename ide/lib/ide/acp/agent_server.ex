defmodule Ide.Acp.AgentServer do
  @moduledoc """
  ACP agent stdio server.

  ACP stdio messages are newline-delimited JSON-RPC objects.
  """

  alias Ide.Acp.AgentProtocol

  @spec run(keyword()) :: :ok
  def run(opts \\ []) do
    opts
    |> AgentProtocol.new()
    |> loop()
  end

  defp loop(state) do
    case IO.binread(:stdio, :line) do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      line ->
        state =
          case Jason.decode(line) do
            {:ok, message} when is_map(message) ->
              {state, responses} = AgentProtocol.handle_message(message, state)
              Enum.each(responses, &write_message/1)
              state

            _other ->
              state
          end

        loop(state)
    end
  end

  defp write_message(message) do
    IO.binwrite(Jason.encode!(message))
    IO.binwrite("\n")
  end
end
