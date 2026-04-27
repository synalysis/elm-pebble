defmodule Ide.Mcp.Server do
  @moduledoc """
  Minimal MCP JSON-RPC server over stdio with capability-scoped IDE tools.
  """

  alias Ide.Mcp.Protocol

  @spec run(keyword()) :: :ok
  def run(opts \\ []) do
    capabilities = Keyword.get(opts, :capabilities, [:read])
    loop(capabilities)
  end

  @spec loop(term()) :: term()
  defp loop(capabilities) do
    case read_message() do
      {:ok, message} ->
        maybe_respond(message, capabilities)
        loop(capabilities)

      :eof ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  @spec maybe_respond(term(), term()) :: term()
  defp maybe_respond(%{"id" => _id} = request, capabilities) do
    request
    |> Protocol.response(capabilities)
    |> write_message()
  end

  defp maybe_respond(_notification, _capabilities), do: :ok

  @spec read_message() :: term()
  defp read_message do
    with {:ok, content_length} <- read_headers(nil),
         {:ok, payload} <- read_exact(content_length),
         {:ok, message} <- Jason.decode(payload) do
      {:ok, message}
    end
  end

  @spec read_headers(term()) :: term()
  defp read_headers(content_length) do
    case IO.binread(:stdio, :line) do
      :eof ->
        :eof

      {:error, reason} ->
        {:error, reason}

      "\r\n" ->
        case content_length do
          nil -> {:error, :missing_content_length}
          len -> {:ok, len}
        end

      line ->
        parsed_length =
          case String.split(line, ":", parts: 2) do
            [header, value] ->
              if String.downcase(String.trim(header)) == "content-length" do
                case Integer.parse(String.trim(value)) do
                  {len, _} when len >= 0 -> len
                  _ -> content_length
                end
              else
                content_length
              end

            _ ->
              content_length
          end

        read_headers(parsed_length)
    end
  end

  @spec read_exact(term()) :: term()
  defp read_exact(0), do: {:ok, ""}

  defp read_exact(length) when is_integer(length) and length > 0 do
    case IO.binread(:stdio, length) do
      :eof -> {:error, :unexpected_eof}
      {:error, reason} -> {:error, reason}
      payload -> {:ok, payload}
    end
  end

  @spec write_message(term()) :: term()
  defp write_message(payload) do
    encoded = Jason.encode!(payload)
    IO.binwrite("Content-Length: #{byte_size(encoded)}\r\n\r\n")
    IO.binwrite(encoded)
  end
end
