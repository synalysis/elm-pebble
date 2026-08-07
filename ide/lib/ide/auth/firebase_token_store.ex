defmodule Ide.Auth.FirebaseTokenStore do
  @moduledoc """
  Server-side storage for Firebase ID tokens.

  Cookie sessions cannot reliably hold a full JWT (browser ~4KB cookie limit once
  signed). Tokens are keyed by user id and looked up after auth hooks load the user.
  """

  use GenServer

  @table :ide_firebase_id_tokens

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec put(pos_integer(), String.t()) :: :ok
  def put(user_id, token)
      when is_integer(user_id) and user_id > 0 and is_binary(token) do
    trimmed = String.trim(token)

    if trimmed == "" do
      :ok
    else
      ensure_table!()
      true = :ets.insert(@table, {user_id, trimmed})
      :ok
    end
  end

  @spec get(pos_integer() | nil) :: String.t() | nil
  def get(nil), do: nil

  def get(user_id) when is_integer(user_id) and user_id > 0 do
    ensure_table!()

    case :ets.lookup(@table, user_id) do
      [{^user_id, token}] when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  def get(_), do: nil

  @spec delete(pos_integer() | nil) :: :ok
  def delete(nil), do: :ok

  def delete(user_id) when is_integer(user_id) and user_id > 0 do
    ensure_table!()
    :ets.delete(@table, user_id)
    :ok
  end

  def delete(_), do: :ok

  @impl true
  def init(_opts) do
    ensure_table!()
    {:ok, %{}}
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
        rescue
          ArgumentError -> :ok
        end

      _tid ->
        :ok
    end
  end
end
