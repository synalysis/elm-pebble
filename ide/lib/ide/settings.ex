defmodule Ide.Settings do
  @moduledoc """
  Lightweight persisted IDE settings storage.
  """

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
      mcp_http_enabled: Map.get(merged, "mcp_http_enabled", true) == true,
      mcp_http_port: parse_port(Map.get(merged, "mcp_http_port", 4000)),
      mcp_http_capabilities:
        parse_capabilities(Map.get(merged, "mcp_http_capabilities", ["read"])),
      acp_agent_enabled: Map.get(merged, "acp_agent_enabled", true) == true,
      acp_agent_capabilities:
        parse_capabilities(Map.get(merged, "acp_agent_capabilities", ["read"]))
    }
  end

  @spec set_auto_format_on_save(boolean()) :: :ok | {:error, term()}
  def set_auto_format_on_save(value) when is_boolean(value) do
    values =
      read_file_values()
      |> Map.put("auto_format_on_save", value)

    write_file_values(values)
  end

  @spec set_debug_mode(boolean()) :: :ok | {:error, term()}
  def set_debug_mode(value) when is_boolean(value) do
    values =
      read_file_values()
      |> Map.put("debug_mode", value)

    write_file_values(values)
  end

  @spec set_formatter_backend(formatter_backend() | String.t()) :: :ok | {:error, term()}
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

  @spec set_editor_mode(editor_mode() | String.t()) :: :ok | {:error, term()}
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

  @spec set_editor_theme(editor_theme() | String.t()) :: :ok | {:error, term()}
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

  @spec set_editor_line_numbers(boolean()) :: :ok | {:error, term()}
  def set_editor_line_numbers(value) when is_boolean(value) do
    values =
      read_file_values()
      |> Map.put("editor_line_numbers", value)

    write_file_values(values)
  end

  @spec set_editor_active_line_highlight(boolean()) :: :ok | {:error, term()}
  def set_editor_active_line_highlight(value) when is_boolean(value) do
    values =
      read_file_values()
      |> Map.put("editor_active_line_highlight", value)

    write_file_values(values)
  end

  @spec set_mcp_http_enabled(boolean()) :: :ok | {:error, term()}
  def set_mcp_http_enabled(value) when is_boolean(value) do
    values =
      read_file_values()
      |> Map.put("mcp_http_enabled", value)

    write_file_values(values)
  end

  @spec set_mcp_http_port(pos_integer() | String.t()) :: :ok | {:error, term()}
  def set_mcp_http_port(value) do
    case normalize_port(value) do
      {:ok, port} ->
        values =
          read_file_values()
          |> Map.put("mcp_http_port", port)

        write_file_values(values)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec set_mcp_http_capabilities([capability() | String.t()] | String.t()) ::
          :ok | {:error, term()}
  def set_mcp_http_capabilities(value) do
    values =
      read_file_values()
      |> Map.put("mcp_http_capabilities", capabilities_to_strings(value))

    write_file_values(values)
  end

  @spec set_acp_agent_enabled(boolean()) :: :ok | {:error, term()}
  def set_acp_agent_enabled(value) when is_boolean(value) do
    values =
      read_file_values()
      |> Map.put("acp_agent_enabled", value)

    write_file_values(values)
  end

  @spec set_acp_agent_capabilities([capability() | String.t()] | String.t()) ::
          :ok | {:error, term()}
  def set_acp_agent_capabilities(value) do
    values =
      read_file_values()
      |> Map.put("acp_agent_capabilities", capabilities_to_strings(value))

    write_file_values(values)
  end

  @spec read_file_values() :: term()
  defp read_file_values do
    path = settings_path()

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

  @spec write_file_values(term()) :: term()
  defp write_file_values(values) do
    path = settings_path()
    parent = Path.dirname(path)

    with :ok <- File.mkdir_p(parent),
         {:ok, encoded} <- Jason.encode(values, pretty: true),
         :ok <- File.write(path, encoded <> "\n") do
      :ok
    end
  end

  @spec settings_path() :: term()
  defp settings_path do
    Application.get_env(:ide, Ide.Settings, [])
    |> Keyword.fetch!(:settings_path)
  end

  @spec parse_editor_mode(term()) :: term()
  defp parse_editor_mode("vim"), do: :vim
  defp parse_editor_mode(_), do: :regular

  @spec parse_formatter_backend(term()) :: formatter_backend()
  defp parse_formatter_backend("elm_format"), do: :elm_format
  defp parse_formatter_backend("elm-format"), do: :elm_format
  defp parse_formatter_backend(_), do: :built_in

  @spec parse_editor_theme(term()) :: term()
  defp parse_editor_theme("dark"), do: :dark
  defp parse_editor_theme("light"), do: :light
  defp parse_editor_theme(_), do: :system

  @spec parse_port(term()) :: pos_integer()
  defp parse_port(value) when is_integer(value) and value >= 1 and value <= 65_535, do: value

  defp parse_port(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {port, ""} when port >= 1 and port <= 65_535 -> port
      _ -> 4000
    end
  end

  defp parse_port(_), do: 4000

  @spec normalize_port(term()) :: {:ok, pos_integer()} | {:error, term()}
  defp normalize_port(value) when is_integer(value) and value >= 1 and value <= 65_535,
    do: {:ok, value}

  defp normalize_port(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {port, ""} when port >= 1 and port <= 65_535 -> {:ok, port}
      _ -> {:error, {:invalid_port, value}}
    end
  end

  defp normalize_port(value), do: {:error, {:invalid_port, value}}

  @spec parse_capabilities(term()) :: [capability()]
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

  @spec normalize_editor_mode(term()) :: term()
  defp normalize_editor_mode(:regular), do: {:ok, :regular}
  defp normalize_editor_mode(:vim), do: {:ok, :vim}
  defp normalize_editor_mode("regular"), do: {:ok, :regular}
  defp normalize_editor_mode("vim"), do: {:ok, :vim}
  defp normalize_editor_mode(other), do: {:error, {:invalid_editor_mode, other}}

  @spec normalize_formatter_backend(term()) ::
          {:ok, formatter_backend()} | {:error, term()}
  defp normalize_formatter_backend(:built_in), do: {:ok, :built_in}
  defp normalize_formatter_backend(:elm_format), do: {:ok, :elm_format}
  defp normalize_formatter_backend("built_in"), do: {:ok, :built_in}
  defp normalize_formatter_backend("elm_format"), do: {:ok, :elm_format}
  defp normalize_formatter_backend("elm-format"), do: {:ok, :elm_format}
  defp normalize_formatter_backend(other), do: {:error, {:invalid_formatter_backend, other}}

  @spec formatter_backend_to_string(formatter_backend()) :: String.t()
  defp formatter_backend_to_string(:elm_format), do: "elm_format"
  defp formatter_backend_to_string(_), do: "built_in"

  @spec normalize_editor_theme(term()) :: term()
  defp normalize_editor_theme(:system), do: {:ok, :system}
  defp normalize_editor_theme(:dark), do: {:ok, :dark}
  defp normalize_editor_theme(:light), do: {:ok, :light}
  defp normalize_editor_theme("system"), do: {:ok, :system}
  defp normalize_editor_theme("dark"), do: {:ok, :dark}
  defp normalize_editor_theme("light"), do: {:ok, :light}
  defp normalize_editor_theme(other), do: {:error, {:invalid_editor_theme, other}}
end
