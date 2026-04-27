defmodule IdeWeb.LspChannel do
  use IdeWeb, :channel

  alias Ide.Lsp.Server

  @impl true
  def join("lsp:" <> project_slug, _payload, socket) do
    {:ok, assign(socket, :lsp_state, Server.new(project_slug))}
  end

  @impl true
  def handle_in("message", %{"message" => raw}, socket) when is_binary(raw) do
    {messages, next_state} = Server.handle(raw, socket.assigns.lsp_state)

    Enum.each(messages, fn message ->
      push(socket, "message", %{"message" => Jason.encode!(message)})
    end)

    {:noreply, assign(socket, :lsp_state, next_state)}
  end

  def handle_in("message", _payload, socket), do: {:noreply, socket}
end
