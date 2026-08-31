defmodule IdeWeb.LspChannel do
  use IdeWeb, :channel

  alias Ide.Auth
  alias Ide.Lsp.Server
  alias Ide.Projects

  @impl true
  @spec join(term(), term(), term()) :: term()

  def join("lsp:" <> project_slug, _payload, socket) do
    user = socket.assigns[:current_user]

    if user do
      Process.put(:ide_current_user, user)
    end

    cond do
      not Auth.public_mode?() ->
        {:ok, assign(socket, :lsp_state, Server.new(project_slug))}

      is_nil(user) ->
        {:error, %{reason: "unauthorized"}}

      is_nil(Projects.get_project_by_slug(project_slug, user)) ->
        {:error, %{reason: "unauthorized"}}

      true ->
        {:ok, assign(socket, :lsp_state, Server.new(project_slug))}
    end
  end

  @impl true
  @spec handle_in(term(), map() | term(), term()) :: term()

  def handle_in("message", %{"message" => raw}, socket) when is_binary(raw) do
    {messages, next_state} = Server.handle(raw, socket.assigns.lsp_state)

    Enum.each(messages, fn message ->
      push(socket, "message", %{"message" => Jason.encode!(message)})
    end)

    {:noreply, assign(socket, :lsp_state, next_state)}
  end

  def handle_in("message", _payload, socket), do: {:noreply, socket}
end
