defmodule Ide.Settings do
  @moduledoc """
  Lightweight persisted IDE settings storage.
  """

  alias Ide.Auth
  alias Ide.Auth.User

  @defaults %{
    "auto_format_on_save" => false,
    "debug_mode" => false,
    "formatter_backend" => "elm_format",
    "editor_mode" => "regular",
    "editor_theme" => "system",
    "editor_line_numbers" => true,
    "editor_active_line_highlight" => true,
    "mcp_http_enabled" => true,
    "mcp_http_port" => 4000,
    "mcp_http_capabilities" => ["read"],
    "acp_agent_enabled" => true,
    "acp_agent_capabilities" => ["read"]
  }

  @type editor_mode :: :regular | :vim
  @type editor_theme :: :system | :dark | :light
  @type formatter_backend :: :built_in | :elm_format
  @type capability :: :read | :edit | :build
  @type wire_input :: String.t() | integer() | boolean() | list() | nil
  @type file_values :: %{optional(String.t()) => boolean() | String.t() | integer() | list()}
  @type settings_write_result :: :ok | {:error, File.posix() | Jason.EncodeError.t()}
  @type settings_error ::
          File.posix()
          | Jason.EncodeError.t()
          | {:invalid_port, wire_input()}
          | {:invalid_editor_mode, wire_input()}
          | {:invalid_formatter_backend, wire_input()}
          | {:invalid_editor_theme, wire_input()}
  @type settings_set_result :: :ok | {:error, settings_error()}

  @type values :: %{
          auto_format_on_save: boolean(),
          debug_mode: boolean(),
          formatter_backend: formatter_backend(),
          editor_mode: editor_mode(),
          editor_theme: editor_theme(),
          editor_line_numbers: boolean(),
          editor_active_line_highlight: boolean(),
          mcp_http_enabled: boolean(),
          mcp_http_port: pos_integer(),
          mcp_http_capabilities: [capability()],
          acp_agent_enabled: boolean(),
          acp_agent_capabilities: [capability()]
        }

  @spec current() :: values()
  def current do
    file_values = read_file_values()

    merged =
      @defaults
      |> Map.merge(file_values)

    %{
      auto_format_on_save: Map.get(merged, "auto_format_on_save", false) == true,
      debug_mode: Map.get(merged, "debug_mode", false) == true,
      formatter_backend:
        parse_formatter_backend(Map.get(merged, "formatter_backend", "elm_format")),
      editor_mode: parse_editor_mode(Map.get(merged, "editor_mode", "regular")),
      editor_theme: parse_editor_theme(Map.get(merged, "editor_theme", "system")),
      editor_line_numbers: Map.get(merged, "editor_line_numbers", true) == true,
      editor_active_line_highlight: Map.get(merged, "editor_active_line_highlight", true) == true,
      mcp_http_enabled: Auth.mcp_enabled?() and Map.get(merged, "mcp_http_enabled", true) == true,
      mcp_http_port: parse_port(Map.get(merged, "mcp_http_port", 4000)),
      mcp_http_capabilities:
        parse_capabilities(Map.get(merged, "mcp_http_capabilities", ["read"])),
      acp_agent_enabled:
        Auth.mcp_enabled?() and Map.get(merged, "acp_agent_enabled", true) == true,
      acp_agent_capabilities:
        parse_capabilities(Map.get(merged, "acp_agent_capabilities", ["read"]))
    }
  end

  @spec set_auto_format_on_save(boolean()) :: settings_set_result()
  def set_auto_format_on_save(value) when is_boolean(value) do
    values =
      read_file_values()
      |> Map.put("auto_format_on_save", value)

    write_file_values(values)
  end

  @spec set_debug_mode(boolean()) :: settings_set_result()
  def set_debug_mode(value) when is_boolean(value) do
    values =
      read_file_values()
      |> Map.put("debug_mode", value)

    write_file_values(values)
  end

  @spec set_formatter_backend(formatter_backend() | String.t()) :: settings_set_result()
  def set_formatter_backend(value) do
    case normalize_formatter_backend(value) do
      {:ok, backend} ->
        values =
          read_file_values()
          |> Map.put("formatter_backend", formatter_backend_to_string(backend))

        write_file_values(values)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec set_editor_mode(editor_mode() | String.t()) :: settings_set_result()
  def set_editor_mode(value) do
    case normalize_editor_mode(value) do
      {:ok, mode} ->
        values =
          read_file_values()
          |> Map.put("editor_mode", Atom.to_string(mode))

        write_file_values(values)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec set_editor_theme(editor_theme() | String.t()) :: settings_set_result()
  def set_editor_theme(value) do
    case normalize_editor_theme(value) do
      {:ok, theme} ->
        values =
          read_file_values()
          |> Map.put("editor_theme", Atom.to_string(theme))

        write_file_values(values)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec set_editor_line_numbers(boolean()) :: settings_set_result()
  def set_editor_line_numbers(value) when is_boolean(value) do
    values =
      read_file_values()
      |> Map.put("editor_line_numbers", value)

    write_file_values(values)
  end

  @spec set_editor_active_line_highlight(boolean()) :: settings_set_result()
  def set_editor_active_line_highlight(value) when is_boolean(value) do
    values =
      read_file_values()
      |> Map.put("editor_active_line_highlight", value)

    write_file_values(values)
  end

  @spec set_mcp_http_enabled(boolean()) :: settings_set_result()
  def set_mcp_http_enabled(value) when is_boolean(value) do
    if Auth.mcp_enabled?() do
      values =
        read_file_values()
        |> Map.put("mcp_http_enabled", value)

      write_file_values(values)
    else
      :ok
    end
  end

  @spec set_mcp_http_port(pos_integer() | String.t()) :: settings_set_result()
  def set_mcp_http_port(value) do
    if Auth.mcp_enabled?() do
      case normalize_port(value) do
        {:ok, port} ->
          values =
            read_file_values()
            |> Map.put("mcp_http_port", port)

          write_file_values(values)

        {:error, reason} ->
          {:error, reason}
      end
    else
      :ok
    end
  end

  @spec set_mcp_http_capabilities([capability() | String.t()] | String.t()) ::
          settings_set_result()
  def set_mcp_http_capabilities(value) do
    if Auth.mcp_enabled?() do
      values =
        read_file_values()
        |> Map.put("mcp_http_capabilities", capabilities_to_strings(value))

      write_file_values(values)
    else
      :ok
    end
  end

  @spec set_acp_agent_enabled(boolean()) :: settings_set_result()
  def set_acp_agent_enabled(value) when is_boolean(value) do
    if Auth.mcp_enabled?() do
      values =
        read_file_values()
        |> Map.put("acp_agent_enabled", value)

      write_file_values(values)
    else
      :ok
    end
  end

  @spec set_acp_agent_capabilities([capability() | String.t()] | String.t()) ::
          settings_set_result()
  def set_acp_agent_capabilities(value) do
    if Auth.mcp_enabled?() do
      values =
        read_file_values()
        |> Map.put("acp_agent_capabilities", capabilities_to_strings(value))

      write_file_values(values)
    else
      :ok
    end
  end

  @doc """
  Returns the on-disk settings path for `user` in public mode, or the global
  settings path in local mode.
  """
  @spec user_settings_path(User.t() | integer()) :: String.t() | nil
  def user_settings_path(%User{id: id}), do: user_settings_path(id)

  def user_settings_path(id) when is_integer(id) do
    if Auth.public_mode?() do
      Path.join([data_root(), "users", Integer.to_string(id), "settings.json"])
    else
      global_settings_path()
    end
  end

  @doc """
  Removes a user's persisted settings file in public mode.
  """
  @spec delete_user_settings(User.t()) :: :ok
  def delete_user_settings(%User{id: id}) when is_integer(id) do
    if Auth.public_mode?() do
      path = user_settings_path(id)

      if is_binary(path) and File.exists?(path) do
        File.rm(path)
      end

      user_dir = Path.dirname(path)

      case File.ls(user_dir) do
        {:ok, []} -> File.rmdir(user_dir)
        _ -> :ok
      end
    end

    :ok
  end

  @spec data_root() :: String.t()
  def data_root do
    Application.get_env(:ide, Ide.Settings, [])
    |> Keyword.get(:data_root, "/var/lib/ide")
  end

  @spec read_file_values() :: file_values()
  defp read_file_values do
    case settings_path() do
      nil ->
        %{}

      path ->
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
  end

  @spec write_file_values(file_values()) :: settings_write_result() | {:error, :no_settings_scope}
  defp write_file_values(values) do
    case settings_path() do
      nil ->
        {:error, :no_settings_scope}

      path ->
        parent = Path.dirname(path)

        with :ok <- File.mkdir_p(parent),
             {:ok, encoded} <- Jason.encode(values, pretty: true),
             :ok <- File.write(path, encoded <> "\n") do
          :ok
        end
    end
  end

  @spec settings_path() :: String.t() | nil
  defp settings_path do
    config = Application.get_env(:ide, Ide.Settings, [])

    case Keyword.get(config, :settings_path) do
      path when is_binary(path) and path != "" ->
        path

      _ ->
        resolve_settings_path()
    end
  end

  @spec resolve_settings_path() :: String.t() | nil
  defp resolve_settings_path do
    if Auth.public_mode?() do
      case Process.get(:ide_current_user) do
        %{id: id} when is_integer(id) -> user_settings_path(id)
        _ -> nil
      end
    else
      global_settings_path()
    end
  end

  @spec global_settings_path() :: String.t()
  defp global_settings_path do
    System.get_env("SETTINGS_FILE") || Path.join(data_root(), "config/settings.json")
  end

  @spec parse_editor_mode(wire_input()) :: editor_mode()
  defp parse_editor_mode("vim"), do: :vim
  defp parse_editor_mode(_), do: :regular

  @spec parse_formatter_backend(wire_input()) :: formatter_backend()
  defp parse_formatter_backend("elm_format"), do: :elm_format
  defp parse_formatter_backend("elm-format"), do: :elm_format
  defp parse_formatter_backend(_), do: :built_in

  @spec parse_editor_theme(wire_input()) :: editor_theme()
  defp parse_editor_theme("dark"), do: :dark
  defp parse_editor_theme("light"), do: :light
  defp parse_editor_theme(_), do: :system

  @spec parse_port(wire_input()) :: pos_integer()
  defp parse_port(value) when is_integer(value) and value >= 1 and value <= 65_535, do: value

  defp parse_port(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {port, ""} when port >= 1 and port <= 65_535 -> port
      _ -> 4000
    end
  end

  defp parse_port(_), do: 4000

  @spec normalize_port(wire_input()) ::
          {:ok, pos_integer()} | {:error, {:invalid_port, wire_input()}}
  defp normalize_port(value) when is_integer(value) and value >= 1 and value <= 65_535,
    do: {:ok, value}

  defp normalize_port(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {port, ""} when port >= 1 and port <= 65_535 -> {:ok, port}
      _ -> {:error, {:invalid_port, value}}
    end
  end

  defp normalize_port(value), do: {:error, {:invalid_port, value}}

  @spec parse_capabilities(wire_input()) :: [capability()]
  defp parse_capabilities(value) do
    value
    |> normalize_capability_input()
    |> Enum.map(&parse_capability/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> [:read]
      list -> Enum.uniq(list)
    end
  end

  defp capabilities_to_strings(value) do
    value
    |> parse_capabilities()
    |> Enum.map(&Atom.to_string/1)
  end

  defp normalize_capability_input(value) when is_binary(value) do
    String.split(value, ",", trim: true)
  end

  defp normalize_capability_input(value) when is_list(value), do: value
  defp normalize_capability_input(_), do: []

  defp parse_capability(:read), do: :read
  defp parse_capability(:edit), do: :edit
  defp parse_capability(:build), do: :build
  defp parse_capability(value) when is_atom(value), do: nil

  defp parse_capability(value) do
    case value |> to_string() |> String.trim() |> String.downcase() do
      "read" -> :read
      "edit" -> :edit
      "build" -> :build
      _ -> nil
    end
  end

  @spec normalize_editor_mode(wire_input()) ::
          {:ok, editor_mode()} | {:error, {:invalid_editor_mode, wire_input()}}
  defp normalize_editor_mode(:regular), do: {:ok, :regular}
  defp normalize_editor_mode(:vim), do: {:ok, :vim}
  defp normalize_editor_mode("regular"), do: {:ok, :regular}
  defp normalize_editor_mode("vim"), do: {:ok, :vim}
  defp normalize_editor_mode(other), do: {:error, {:invalid_editor_mode, other}}

  @spec normalize_formatter_backend(wire_input()) ::
          {:ok, formatter_backend()} | {:error, {:invalid_formatter_backend, wire_input()}}
  defp normalize_formatter_backend(:built_in), do: {:ok, :built_in}
  defp normalize_formatter_backend(:elm_format), do: {:ok, :elm_format}
  defp normalize_formatter_backend("built_in"), do: {:ok, :built_in}
  defp normalize_formatter_backend("elm_format"), do: {:ok, :elm_format}
  defp normalize_formatter_backend("elm-format"), do: {:ok, :elm_format}
  defp normalize_formatter_backend(other), do: {:error, {:invalid_formatter_backend, other}}

  @spec formatter_backend_to_string(formatter_backend()) :: String.t()
  defp formatter_backend_to_string(:elm_format), do: "elm_format"
  defp formatter_backend_to_string(_), do: "built_in"

  @spec normalize_editor_theme(wire_input()) ::
          {:ok, editor_theme()} | {:error, {:invalid_editor_theme, wire_input()}}
  defp normalize_editor_theme(:system), do: {:ok, :system}
  defp normalize_editor_theme(:dark), do: {:ok, :dark}
  defp normalize_editor_theme(:light), do: {:ok, :light}
  defp normalize_editor_theme("system"), do: {:ok, :system}
  defp normalize_editor_theme("dark"), do: {:ok, :dark}
  defp normalize_editor_theme("light"), do: {:ok, :light}
  defp normalize_editor_theme(other), do: {:error, {:invalid_editor_theme, other}}
end
