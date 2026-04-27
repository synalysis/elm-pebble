defmodule Ide.GitHub.Credentials do
  @moduledoc """
  Lightweight persisted storage for GitHub OAuth credentials.
  """

  @type t :: %{
          connected?: boolean(),
          access_token: String.t() | nil,
          token_type: String.t() | nil,
          scope: String.t() | nil,
          user_login: String.t() | nil,
          user_id: integer() | nil,
          connected_at: String.t() | nil,
          last_checked_at: String.t() | nil
        }

  @spec current() :: t()
  def current do
    values = read_file_values()

    %{
      connected?: is_binary(values["access_token"]) and String.trim(values["access_token"]) != "",
      access_token: values["access_token"],
      token_type: values["token_type"],
      scope: values["scope"],
      user_login: values["user_login"],
      user_id: parse_int(values["user_id"]),
      connected_at: values["connected_at"],
      last_checked_at: values["last_checked_at"]
    }
  end

  @spec put(map()) :: :ok | {:error, term()}
  def put(attrs) when is_map(attrs) do
    cleaned =
      attrs
      |> Map.new()
      |> maybe_put("access_token")
      |> maybe_put("token_type")
      |> maybe_put("scope")
      |> maybe_put("user_login")
      |> maybe_put("connected_at")
      |> maybe_put("last_checked_at")
      |> maybe_put_int("user_id")

    merged =
      read_file_values()
      |> Map.merge(cleaned)

    write_file_values(merged)
  end

  @spec clear() :: :ok | {:error, term()}
  def clear do
    write_file_values(%{})
  end

  @spec connected?() :: boolean()
  def connected? do
    current().connected?
  end

  @spec access_token() :: String.t() | nil
  def access_token do
    current().access_token
  end

  @spec read_file_values() :: map()
  defp read_file_values do
    path = credentials_path()

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, values} when is_map(values) -> values
          _ -> %{}
        end

      {:error, _reason} ->
        %{}
    end
  end

  @spec write_file_values(map()) :: :ok | {:error, term()}
  defp write_file_values(values) do
    path = credentials_path()
    parent = Path.dirname(path)

    with :ok <- File.mkdir_p(parent),
         {:ok, encoded} <- Jason.encode(values, pretty: true),
         :ok <- File.write(path, encoded <> "\n") do
      :ok
    end
  end

  @spec credentials_path() :: String.t()
  defp credentials_path do
    Application.get_env(:ide, Ide.GitHub, [])
    |> Keyword.fetch!(:credentials_path)
  end

  @spec maybe_put(map(), String.t()) :: map()
  defp maybe_put(map, key) do
    value = Map.get(map, key) || Map.get(map, String.to_atom(key))
    put_clean_string(map, key, value)
  end

  @spec maybe_put_int(map(), String.t()) :: map()
  defp maybe_put_int(map, key) do
    value = Map.get(map, key) || Map.get(map, String.to_atom(key))

    case parse_int(value) do
      nil -> Map.delete(map, key)
      int -> Map.put(map, key, int)
    end
  end

  @spec put_clean_string(map(), String.t(), term()) :: map()
  defp put_clean_string(map, _key, nil), do: map

  defp put_clean_string(map, key, value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: Map.delete(map, key), else: Map.put(map, key, trimmed)
  end

  defp put_clean_string(map, _key, _value), do: map

  @spec parse_int(term()) :: integer() | nil
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_), do: nil
end
