defmodule IdeWeb.UserSocket do
  use Phoenix.Socket

  require Logger

  alias Ide.Auth

  channel "lsp:*", IdeWeb.LspChannel
  channel "emulator_vnc:*", IdeWeb.EmulatorVncChannel

  @impl true
  @spec connect(term(), term(), term()) :: term()

  def connect(params, socket, connect_info) do
    Logger.info(
      "user socket connect transport=#{inspect(Map.get(connect_info, :transport))} params_keys=#{inspect(Map.keys(params || %{}))}"
    )

    session = Map.get(connect_info, :session) || %{}
    user = Auth.get_user(session_user_id(session))

    cond do
      Auth.public_mode?() and is_nil(user) ->
        :error

      true ->
        {:ok, assign(socket, :current_user, user)}
    end
  end

  @impl true
  @spec id(term()) :: term()

  def id(%{assigns: %{current_user: %{id: id}}}) when is_integer(id), do: "user_socket:#{id}"
  def id(_socket), do: nil

  @spec session_user_id(map()) :: integer() | nil
  defp session_user_id(session) when is_map(session) do
    case Map.get(session, "user_id") || Map.get(session, :user_id) do
      id when is_integer(id) and id > 0 ->
        id

      id when is_binary(id) ->
        case Integer.parse(id) do
          {int, ""} when int > 0 -> int
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp session_user_id(_), do: nil
end
