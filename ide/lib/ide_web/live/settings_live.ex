defmodule IdeWeb.SettingsLive do
  use IdeWeb, :live_view

  alias Ide.GitHub.AuthFlow
  alias Ide.Settings

  @impl true
  @spec mount(term(), term(), term()) :: term()
  def mount(_params, _session, socket) do
    settings = Settings.current()

    {:ok,
     socket
     |> assign(:page_title, "IDE Settings")
     |> assign(:return_to, "/projects")
     |> assign(:github_status, AuthFlow.status())
     |> assign(:github_oauth_ready, AuthFlow.oauth_client_configured?())
     |> assign(:github_flow, nil)
     |> assign(:settings, settings)
     |> assign_snippet_state("generic_http_mcp", settings)
     |> assign(:form, settings_form(settings))}
  end

  @impl true
  @spec handle_params(term(), term(), term()) :: term()
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :return_to, sanitize_return_to(params["return_to"]))}
  end

  @impl true
  @spec handle_event(term(), term(), term()) :: term()
  def handle_event("save", %{"settings" => params}, socket) do
    auto_format = parse_checkbox(params["auto_format_on_save"])
    debug_mode = parse_checkbox(params["debug_mode"])
    formatter_backend = parse_formatter_backend(params["formatter_backend"])
    editor_mode = parse_editor_mode(params["editor_mode"])
    editor_theme = parse_editor_theme(params["editor_theme"])
    editor_line_numbers = parse_checkbox(params["editor_line_numbers"])
    editor_active_line_highlight = parse_checkbox(params["editor_active_line_highlight"])
    mcp_http_enabled = parse_checkbox(params["mcp_http_enabled"])
    mcp_http_port = params["mcp_http_port"]
    mcp_http_capabilities = parse_capability_params(params["mcp_http_capabilities"])
    acp_agent_enabled = parse_checkbox(params["acp_agent_enabled"])
    acp_agent_capabilities = parse_capability_params(params["acp_agent_capabilities"])

    with :ok <- Settings.set_auto_format_on_save(auto_format),
         :ok <- Settings.set_debug_mode(debug_mode),
         :ok <- Settings.set_formatter_backend(formatter_backend),
         :ok <- Settings.set_editor_mode(editor_mode),
         :ok <- Settings.set_editor_theme(editor_theme),
         :ok <- Settings.set_editor_line_numbers(editor_line_numbers),
         :ok <- Settings.set_editor_active_line_highlight(editor_active_line_highlight),
         :ok <- Settings.set_mcp_http_enabled(mcp_http_enabled),
         :ok <- Settings.set_mcp_http_port(mcp_http_port),
         :ok <- Settings.set_mcp_http_capabilities(mcp_http_capabilities),
         :ok <- Settings.set_acp_agent_enabled(acp_agent_enabled),
         :ok <- Settings.set_acp_agent_capabilities(acp_agent_capabilities) do
      settings = %{
        auto_format_on_save: auto_format,
        debug_mode: debug_mode,
        formatter_backend: formatter_backend,
        editor_mode: editor_mode,
        editor_theme: editor_theme,
        editor_line_numbers: editor_line_numbers,
        editor_active_line_highlight: editor_active_line_highlight,
        mcp_http_enabled: mcp_http_enabled,
        mcp_http_port: parse_saved_port(mcp_http_port),
        mcp_http_capabilities: mcp_http_capabilities,
        acp_agent_enabled: acp_agent_enabled,
        acp_agent_capabilities: acp_agent_capabilities
      }

      {:noreply,
       socket
       |> assign(:settings, settings)
       |> assign_snippet_state(socket.assigns.snippet_target, settings)
       |> assign(:form, settings_form(settings))
       |> push_event("ide-theme-changed", %{theme: Atom.to_string(editor_theme)})
       |> put_flash(:info, "Settings saved.")
       |> schedule_info_flash_clear()}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not save settings: #{inspect(reason)}")}
    end
  end

  def handle_event("select-snippet-target", %{"snippet_target" => target}, socket) do
    {:noreply, assign_snippet_state(socket, target, socket.assigns.settings)}
  end

  def handle_event("github-connect", _params, socket) do
    case AuthFlow.start_device_flow() do
      {:ok, flow} ->
        now_ms = System.system_time(:millisecond)
        interval_ms = max(1, flow["interval"]) * 1_000

        next_flow =
          flow
          |> Map.put("status", "waiting_for_authorization")
          |> Map.put("started_at_ms", now_ms)
          |> Map.put("expires_at_ms", now_ms + max(1, flow["expires_in"]) * 1_000)
          |> Map.put("interval_ms", interval_ms)
          |> Map.put("last_error", nil)

        _ = Process.send_after(self(), {:github_poll, flow["device_code"]}, interval_ms)

        {:noreply, assign(socket, :github_flow, next_flow)}

      {:error, :oauth_client_id_missing} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "GitHub OAuth client ID is not configured. Set GITHUB_OAUTH_CLIENT_ID first."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, github_connect_error_message(reason))}
    end
  end

  def handle_event("github-disconnect", _params, socket) do
    case AuthFlow.disconnect() do
      :ok ->
        {:noreply,
         socket
         |> assign(:github_status, AuthFlow.status())
         |> assign(:github_flow, nil)
         |> put_flash(:info, "GitHub disconnected.")
         |> schedule_info_flash_clear()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not disconnect GitHub: #{inspect(reason)}")}
    end
  end

  @impl true
  @spec handle_info(term(), term()) :: term()
  def handle_info(:clear_info_flash, socket) do
    {:noreply, clear_flash(socket, :info)}
  end

  def handle_info({:github_poll, device_code}, socket) do
    flow = socket.assigns.github_flow || %{}
    now_ms = System.system_time(:millisecond)
    expires_at_ms = flow["expires_at_ms"] || now_ms

    cond do
      flow == %{} ->
        {:noreply, socket}

      flow["device_code"] != device_code ->
        {:noreply, socket}

      now_ms >= expires_at_ms ->
        {:noreply,
         socket
         |> assign(:github_flow, Map.put(flow, "status", "expired"))
         |> put_flash(:error, "GitHub authorization expired. Start connect again.")}

      true ->
        case AuthFlow.poll_and_connect(device_code) do
          {:ok, status} ->
            {:noreply,
             socket
             |> assign(:github_status, status)
             |> assign(:github_flow, nil)
             |> put_flash(:info, "GitHub connected as #{status.user_login}.")
             |> schedule_info_flash_clear()}

          {:error, {:oauth_error, %{"error" => "authorization_pending"}}} ->
            interval_ms = flow["interval_ms"] || 5_000
            _ = Process.send_after(self(), {:github_poll, device_code}, interval_ms)

            {:noreply,
             assign(socket, :github_flow, Map.put(flow, "status", "waiting_for_authorization"))}

          {:error, {:oauth_error, %{"error" => "slow_down"}}} ->
            interval_ms = max((flow["interval_ms"] || 5_000) + 5_000, 5_000)
            _ = Process.send_after(self(), {:github_poll, device_code}, interval_ms)

            {:noreply,
             assign(
               socket,
               :github_flow,
               flow |> Map.put("status", "slowing_down") |> Map.put("interval_ms", interval_ms)
             )}

          {:error, {:oauth_error, %{"error" => "access_denied"}}} ->
            {:noreply,
             socket
             |> assign(:github_flow, Map.put(flow, "status", "denied"))
             |> put_flash(:error, "GitHub authorization was denied.")}

          {:error, {:oauth_error, %{"error" => "expired_token"}}} ->
            {:noreply,
             socket
             |> assign(:github_flow, Map.put(flow, "status", "expired"))
             |> put_flash(:error, "GitHub authorization expired. Start connect again.")}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(
               :github_flow,
               flow |> Map.put("status", "error") |> Map.put("last_error", inspect(reason))
             )
             |> put_flash(:error, "Could not complete GitHub connect flow: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  @spec render(term()) :: term()
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl space-y-6 p-6">
      <header class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold text-zinc-900">IDE Settings</h1>
          <p class="mt-1 text-sm text-zinc-600">Configure editor behavior and workflow defaults.</p>
        </div>
        <.link navigate={@return_to} class="rounded bg-zinc-100 px-3 py-2 text-sm">
          &lt; Back
        </.link>
      </header>

      <section class="rounded-lg border border-zinc-200 bg-white p-5 shadow-sm">
        <div class="flex items-start justify-between gap-3">
          <div>
            <h2 class="text-base font-semibold">GitHub Integration</h2>
            <p class="mt-1 text-sm text-zinc-600">
              Connect once globally, then configure and push individual projects.
            </p>
            <p class="mt-2 text-xs text-zinc-600">{github_status_line(@github_status)}</p>
            <p :if={not @github_oauth_ready} class="mt-2 text-xs text-amber-700">
              GitHub OAuth is not configured. Set `GITHUB_OAUTH_CLIENT_ID` and restart the IDE.
            </p>
          </div>
          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click="github-connect"
              disabled={not @github_oauth_ready}
              class={[
                "rounded px-3 py-2 text-xs font-medium",
                @github_oauth_ready && "bg-zinc-900 text-white hover:bg-zinc-800",
                not @github_oauth_ready && "cursor-not-allowed bg-zinc-200 text-zinc-500"
              ]}
            >
              {if @github_status.connected?, do: "Reconnect", else: "Connect to GitHub"}
            </button>
            <button
              :if={@github_status.connected?}
              type="button"
              phx-click="github-disconnect"
              class="rounded bg-zinc-100 px-3 py-2 text-xs font-medium text-zinc-800 hover:bg-zinc-200"
            >
              Disconnect
            </button>
          </div>
        </div>

        <div :if={@github_flow} class="mt-4 rounded border border-zinc-200 bg-zinc-50 p-3 text-xs">
          <p class="font-semibold text-zinc-800">Authorize this IDE in GitHub</p>
          <p class="mt-1 text-zinc-700">
            Open:
            <a
              href={@github_flow["verification_uri"]}
              target="_blank"
              rel="noopener noreferrer"
              class="font-mono text-blue-700 underline"
            >
              {@github_flow["verification_uri"]}
            </a>
          </p>
          <p :if={@github_flow["verification_uri_complete"]} class="mt-1 text-zinc-700">
            Quick link:
            <a
              href={@github_flow["verification_uri_complete"]}
              target="_blank"
              rel="noopener noreferrer"
              class="font-mono text-blue-700 underline"
            >
              open and approve
            </a>
          </p>
          <p class="mt-2 text-zinc-700">
            User code:
            <span class="rounded bg-zinc-200 px-2 py-1 font-mono font-semibold">
              {@github_flow["user_code"]}
            </span>
          </p>
          <p class="mt-2 text-zinc-600">
            Status: {github_flow_status_label(@github_flow["status"])}
          </p>
          <p
            :if={is_binary(@github_flow["last_error"]) and @github_flow["last_error"] != ""}
            class="mt-1 text-rose-700"
          >
            Last error: {@github_flow["last_error"]}
          </p>
        </div>
      </section>

      <section class="rounded-lg border border-zinc-200 bg-white p-5 shadow-sm">
        <.form for={@form} phx-submit="save" class="space-y-4">
          <label class="flex items-start gap-3">
            <input
              type="checkbox"
              name="settings[auto_format_on_save]"
              value="true"
              checked={@settings.auto_format_on_save}
              class="mt-1 h-4 w-4 rounded border-zinc-300"
            />
            <span>
              <span class="block text-sm font-medium text-zinc-900">
                Auto-format Elm files on save
              </span>
              <span class="block text-xs text-zinc-600">
                If formatting fails to parse, the file is still saved unchanged.
              </span>
            </span>
          </label>

          <label class="flex flex-col gap-2">
            <span class="block text-sm font-medium text-zinc-900">Elm formatter</span>
            <span class="block text-xs text-zinc-600">
              Choose the built-in formatter or the external elm-format command for manual Format
              and auto-format-on-save.
            </span>
            <select
              name="settings[formatter_backend]"
              class="mt-1 w-full max-w-xs rounded border border-zinc-300 bg-white px-3 py-2 text-sm"
            >
              <option value="built_in" selected={@settings.formatter_backend == :built_in}>
                Built-in formatter (experimental)
              </option>
              <option value="elm_format" selected={@settings.formatter_backend == :elm_format}>
                elm-format
              </option>
            </select>
          </label>

          <label class="flex flex-col gap-2">
            <span class="block text-sm font-medium text-zinc-900">Editor mode</span>
            <span class="block text-xs text-zinc-600">
              Regular mode keeps current shortcuts. Vim mode enables modal navigation and editing.
            </span>
            <select
              name="settings[editor_mode]"
              class="mt-1 w-full max-w-xs rounded border border-zinc-300 bg-white px-3 py-2 text-sm"
            >
              <option value="regular" selected={@settings.editor_mode == :regular}>Regular</option>
              <option value="vim" selected={@settings.editor_mode == :vim}>Vim</option>
            </select>
          </label>

          <label class="flex flex-col gap-2">
            <span class="block text-sm font-medium text-zinc-900">Theme</span>
            <select
              name="settings[editor_theme]"
              class="mt-1 w-full max-w-xs rounded border border-zinc-300 bg-white px-3 py-2 text-sm"
            >
              <option value="system" selected={@settings.editor_theme == :system}>System</option>
              <option value="dark" selected={@settings.editor_theme == :dark}>Dark</option>
              <option value="light" selected={@settings.editor_theme == :light}>Light</option>
            </select>
          </label>

          <label class="flex items-start gap-3">
            <input
              type="checkbox"
              name="settings[editor_line_numbers]"
              value="true"
              checked={@settings.editor_line_numbers}
              class="mt-1 h-4 w-4 rounded border-zinc-300"
            />
            <span>
              <span class="block text-sm font-medium text-zinc-900">
                Line numbers
              </span>
              <span class="block text-xs text-zinc-600">
                Show line numbers in the editor gutter.
              </span>
            </span>
          </label>

          <label class="flex items-start gap-3">
            <input
              type="checkbox"
              name="settings[editor_active_line_highlight]"
              value="true"
              checked={@settings.editor_active_line_highlight}
              class="mt-1 h-4 w-4 rounded border-zinc-300"
            />
            <span>
              <span class="block text-sm font-medium text-zinc-900">
                Active line highlight
              </span>
              <span class="block text-xs text-zinc-600">
                Highlight the line containing the cursor.
              </span>
            </span>
          </label>

          <label class="flex items-start gap-3">
            <input
              type="checkbox"
              name="settings[debug_mode]"
              value="true"
              checked={@settings.debug_mode}
              class="mt-1 h-4 w-4 rounded border-zinc-300"
            />
            <span>
              <span class="block text-sm font-medium text-zinc-900">
                Debug mode
              </span>
              <span class="block text-xs text-zinc-600">
                Show tokenizer stats and extra diagnostic/debug UI details.
              </span>
            </span>
          </label>

          <div class="rounded border border-zinc-200 bg-zinc-50 p-4">
            <h2 class="text-sm font-semibold text-zinc-900">MCP / ACP access</h2>
            <p class="mt-1 text-xs text-zinc-600">
              Configure the IDE integration surfaces used by external agents and MCP clients.
              Port changes apply after restarting the IDE server.
            </p>

            <div class="mt-4 grid gap-4 md:grid-cols-2">
              <div class="space-y-3">
                <label class="flex items-start gap-3">
                  <input
                    type="checkbox"
                    name="settings[mcp_http_enabled]"
                    value="true"
                    checked={@settings.mcp_http_enabled}
                    class="mt-1 h-4 w-4 rounded border-zinc-300"
                  />
                  <span>
                    <span class="block text-sm font-medium text-zinc-900">
                      Enable remote MCP HTTP endpoint
                    </span>
                    <span class="block text-xs text-zinc-600">
                      Serves POST /api/mcp for URL-based MCP clients.
                    </span>
                  </span>
                </label>

                <label class="flex flex-col gap-2">
                  <span class="block text-sm font-medium text-zinc-900">MCP HTTP port</span>
                  <input
                    type="number"
                    min="1"
                    max="65535"
                    name="settings[mcp_http_port]"
                    value={@settings.mcp_http_port}
                    class="w-full max-w-xs rounded border border-zinc-300 bg-white px-3 py-2 text-sm"
                  />
                </label>

                <fieldset class="space-y-2">
                  <legend class="text-sm font-medium text-zinc-900">Remote MCP access rights</legend>
                  <.capability_checkbox
                    name="settings[mcp_http_capabilities][]"
                    capability={:read}
                    selected={@settings.mcp_http_capabilities}
                    label="Read"
                  />
                  <.capability_checkbox
                    name="settings[mcp_http_capabilities][]"
                    capability={:edit}
                    selected={@settings.mcp_http_capabilities}
                    label="Edit"
                  />
                  <.capability_checkbox
                    name="settings[mcp_http_capabilities][]"
                    capability={:build}
                    selected={@settings.mcp_http_capabilities}
                    label="Build"
                  />
                </fieldset>
              </div>

              <div class="space-y-3">
                <label class="flex items-start gap-3">
                  <input
                    type="checkbox"
                    name="settings[acp_agent_enabled]"
                    value="true"
                    checked={@settings.acp_agent_enabled}
                    class="mt-1 h-4 w-4 rounded border-zinc-300"
                  />
                  <span>
                    <span class="block text-sm font-medium text-zinc-900">
                      Enable local ACP agent bridge
                    </span>
                    <span class="block text-xs text-zinc-600">
                      Controls the default scope for mix ide.acp_agent.
                    </span>
                  </span>
                </label>

                <fieldset class="space-y-2">
                  <legend class="text-sm font-medium text-zinc-900">ACP agent access rights</legend>
                  <.capability_checkbox
                    name="settings[acp_agent_capabilities][]"
                    capability={:read}
                    selected={@settings.acp_agent_capabilities}
                    label="Read"
                  />
                  <.capability_checkbox
                    name="settings[acp_agent_capabilities][]"
                    capability={:edit}
                    selected={@settings.acp_agent_capabilities}
                    label="Edit"
                  />
                  <.capability_checkbox
                    name="settings[acp_agent_capabilities][]"
                    capability={:build}
                    selected={@settings.acp_agent_capabilities}
                    label="Build"
                  />
                </fieldset>
              </div>
            </div>

            <div class="mt-5 space-y-4 border-t border-zinc-200 pt-4">
              <div>
                <h3 class="text-sm font-semibold text-zinc-900">Editor configuration snippets</h3>
                <p class="mt-1 text-xs text-zinc-600">
                  Choose your client/editor and copy the matching configuration. The snippet reflects
                  the access rights and port selected above.
                </p>
              </div>

              <label class="flex flex-col gap-2">
                <span class="text-sm font-medium text-zinc-900">Client / editor</span>
                <select
                  name="snippet_target"
                  phx-change="select-snippet-target"
                  class="w-full max-w-md rounded border border-zinc-300 bg-white px-3 py-2 text-sm"
                >
                  <option
                    :for={option <- @snippet_options}
                    value={option.value}
                    selected={option.value == @snippet_target}
                  >
                    {option.label}
                  </option>
                </select>
              </label>

              <.snippet_card
                id="editor-config-snippet"
                title={@selected_snippet.title}
                description={@selected_snippet.description}
                snippet={@selected_snippet.snippet}
              />
            </div>
          </div>

          <.button>Save settings</.button>
        </.form>
      </section>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :capability, :atom, required: true
  attr :selected, :list, required: true
  attr :label, :string, required: true

  defp capability_checkbox(assigns) do
    ~H"""
    <label class="flex items-center gap-2 text-sm text-zinc-700">
      <input
        type="checkbox"
        name={@name}
        value={Atom.to_string(@capability)}
        checked={@capability in @selected}
        class="h-4 w-4 rounded border-zinc-300"
      />
      <span>{@label}</span>
    </label>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :snippet, :string, required: true

  defp snippet_card(assigns) do
    ~H"""
    <div class="overflow-hidden rounded border border-zinc-200 bg-white">
      <div class="flex items-start justify-between gap-3 border-b border-zinc-200 px-3 py-2">
        <div>
          <h4 class="text-xs font-semibold uppercase tracking-wide text-zinc-700">{@title}</h4>
          <p class="mt-1 text-xs text-zinc-500">{@description}</p>
        </div>
        <button
          id={"#{@id}-copy"}
          type="button"
          phx-hook="CopyToClipboard"
          data-copy-text={@snippet}
          class="shrink-0 rounded bg-zinc-900 px-2.5 py-1.5 text-xs font-medium text-white hover:bg-zinc-800"
        >
          Copy
        </button>
      </div>
      <pre class="max-h-72 overflow-auto whitespace-pre-wrap break-words bg-zinc-950 p-3 text-xs leading-relaxed text-zinc-100"><code>{@snippet}</code></pre>
    </div>
    """
  end

  defp settings_form(settings) do
    to_form(
      %{
        "auto_format_on_save" => settings.auto_format_on_save,
        "debug_mode" => settings.debug_mode,
        "formatter_backend" => Atom.to_string(settings.formatter_backend),
        "editor_mode" => Atom.to_string(settings.editor_mode),
        "editor_theme" => Atom.to_string(settings.editor_theme),
        "editor_line_numbers" => settings.editor_line_numbers,
        "editor_active_line_highlight" => settings.editor_active_line_highlight,
        "mcp_http_enabled" => settings.mcp_http_enabled,
        "mcp_http_port" => settings.mcp_http_port,
        "mcp_http_capabilities" => Enum.map(settings.mcp_http_capabilities, &Atom.to_string/1),
        "acp_agent_enabled" => settings.acp_agent_enabled,
        "acp_agent_capabilities" => Enum.map(settings.acp_agent_capabilities, &Atom.to_string/1)
      },
      as: :settings
    )
  end

  @spec parse_checkbox(term()) :: term()
  defp parse_checkbox("true"), do: true
  defp parse_checkbox("on"), do: true
  defp parse_checkbox(_), do: false

  @spec parse_formatter_backend(term()) :: term()
  defp parse_formatter_backend("elm_format"), do: :elm_format
  defp parse_formatter_backend("elm-format"), do: :elm_format
  defp parse_formatter_backend(_), do: :built_in

  defp parse_capability_params(values) when is_list(values) do
    values
    |> Enum.map(&parse_capability/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> [:read]
      capabilities -> Enum.uniq(capabilities)
    end
  end

  defp parse_capability_params(_), do: [:read]

  defp parse_capability("read"), do: :read
  defp parse_capability("edit"), do: :edit
  defp parse_capability("build"), do: :build
  defp parse_capability(_), do: nil

  defp parse_saved_port(value) do
    case Integer.parse(to_string(value)) do
      {port, ""} when port >= 1 and port <= 65_535 -> port
      _ -> 4000
    end
  end

  defp assign_snippet_state(socket, target, settings) do
    target = normalize_snippet_target(target)

    socket
    |> assign(:snippet_options, snippet_options())
    |> assign(:snippet_target, target)
    |> assign(:selected_snippet, snippet_for(target, settings))
  end

  defp snippet_options do
    [
      %{value: "generic_http_mcp", label: "Generic MCP client (remote URL)"},
      %{value: "generic_stdio_mcp", label: "Generic MCP client (local stdio)"},
      %{value: "generic_stdio_acp", label: "Generic ACP client (local stdio agent)"},
      %{value: "zed_http_mcp", label: "Zed (remote MCP context server)"},
      %{value: "zed_stdio_acp", label: "Zed (local ACP external agent)"},
      %{value: "cursor_stdio_mcp", label: "Cursor / Claude Desktop style (local MCP stdio)"}
    ]
  end

  defp normalize_snippet_target(target) do
    known = snippet_options() |> Enum.map(& &1.value)

    if target in known do
      target
    else
      "generic_http_mcp"
    end
  end

  defp snippet_for("generic_http_mcp", settings) do
    %{
      title: "Generic MCP client (remote URL)",
      description: "Use for clients that accept an HTTP MCP server URL.",
      snippet:
        pretty_json(%{
          "mcpServers" => %{
            "elm-pebble-ide" => %{
              "url" => "http://localhost:#{settings.mcp_http_port}/api/mcp"
            }
          }
        })
    }
  end

  defp snippet_for("generic_stdio_mcp", settings) do
    %{
      title: "Generic MCP client (local stdio)",
      description:
        "Use for MCP clients that launch local stdio servers with an mcpServers block.",
      snippet: generic_stdio_mcp_snippet(settings)
    }
  end

  defp snippet_for("generic_stdio_acp", settings) do
    %{
      title: "Generic ACP client (local stdio agent)",
      description: "Use for ACP clients that can launch a custom local stdio agent command.",
      snippet:
        pretty_json(%{
          "command" => "bash",
          "args" => ["-lc", acp_command(settings)],
          "env" => %{}
        })
    }
  end

  defp snippet_for("zed_http_mcp", settings) do
    %{
      title: "Zed remote MCP context server",
      description:
        "Use in Zed settings when the IDE server is already running and reachable by URL.",
      snippet:
        pretty_json(%{
          "context_servers" => %{
            "elm-pebble-ide-remote" => %{
              "url" => "http://localhost:#{settings.mcp_http_port}/api/mcp"
            }
          }
        })
    }
  end

  defp snippet_for("zed_stdio_acp", settings) do
    %{
      title: "Zed local ACP external agent",
      description: "Use in Zed settings when Zed should launch the IDE ACP bridge.",
      snippet:
        pretty_json(%{
          "agent_servers" => %{
            "Elm Pebble IDE" => %{
              "type" => "custom",
              "command" => "bash",
              "args" => ["-lc", acp_command(settings)],
              "env" => %{}
            }
          }
        })
    }
  end

  defp snippet_for("cursor_stdio_mcp", settings) do
    %{
      title: "Cursor / Claude Desktop style MCP stdio",
      description: "Use in clients that expect the common mcpServers JSON shape.",
      snippet: generic_stdio_mcp_snippet(settings)
    }
  end

  defp snippet_for(_target, settings), do: snippet_for("generic_http_mcp", settings)

  defp generic_stdio_mcp_snippet(settings) do
    pretty_json(%{
      "mcpServers" => %{
        "elm-pebble-ide" => %{
          "command" => "bash",
          "args" => ["-lc", mcp_command(settings)],
          "env" => %{}
        }
      }
    })
  end

  defp mcp_command(settings) do
    ide_dir = ide_dir()
    mcp_capabilities = capability_csv(settings.mcp_http_capabilities)

    "cd #{shell_quote(ide_dir)} && exec mix ide.mcp --capabilities #{shell_quote(mcp_capabilities)}"
  end

  defp acp_command(settings) do
    ide_dir = ide_dir()
    acp_capabilities = capability_csv(settings.acp_agent_capabilities)

    "cd #{shell_quote(ide_dir)} && exec mix ide.acp_agent --capabilities #{shell_quote(acp_capabilities)}"
  end

  defp pretty_json(value) do
    Jason.encode!(value, pretty: true)
  end

  defp capability_csv(capabilities) do
    capabilities
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(",")
  end

  defp ide_dir do
    cwd = File.cwd!()

    cond do
      Path.basename(cwd) == "ide" and File.exists?(Path.join(cwd, "mix.exs")) ->
        cwd

      File.exists?(Path.join([cwd, "ide", "mix.exs"])) ->
        Path.join(cwd, "ide")

      true ->
        cwd
    end
  end

  defp shell_quote(value) do
    "'" <> String.replace(to_string(value), "'", "'\"'\"'") <> "'"
  end

  @spec parse_editor_mode(term()) :: term()
  defp parse_editor_mode("vim"), do: :vim
  defp parse_editor_mode(_), do: :regular

  @spec parse_editor_theme(term()) :: term()
  defp parse_editor_theme("dark"), do: :dark
  defp parse_editor_theme("light"), do: :light
  defp parse_editor_theme(_), do: :system

  @spec github_status_line(map()) :: String.t()
  defp github_status_line(%{connected?: true} = status) do
    login = status.user_login || "unknown user"
    scope = status.scope || "unknown scope"
    "Connected as #{login} (scope: #{scope})."
  end

  defp github_status_line(_), do: "Not connected."

  @spec github_flow_status_label(term()) :: String.t()
  defp github_flow_status_label("waiting_for_authorization"), do: "Waiting for authorization..."

  defp github_flow_status_label("slowing_down"),
    do: "Waiting (GitHub requested slower polling)..."

  defp github_flow_status_label("expired"), do: "Expired"
  defp github_flow_status_label("denied"), do: "Access denied"
  defp github_flow_status_label("error"), do: "Error"
  defp github_flow_status_label(_), do: "In progress"

  @spec github_connect_error_message(term()) :: String.t()
  defp github_connect_error_message({:http_error, 404, _body}) do
    "GitHub device-flow endpoint was not found (404). Use a Client ID from a GitHub OAuth App (not a GitHub App) and enable Device Flow for that app."
  end

  defp github_connect_error_message({:http_error, 422, _body}) do
    "GitHub rejected the client ID (422). Verify GITHUB_OAUTH_CLIENT_ID points to a valid OAuth App client ID."
  end

  defp github_connect_error_message({:http_error, status, _body}) when is_integer(status) do
    "Could not start GitHub connect flow (HTTP #{status}). Check OAuth app configuration and network access."
  end

  defp github_connect_error_message(reason) do
    "Could not start GitHub connect flow: #{inspect(reason)}"
  end

  @spec schedule_info_flash_clear(term()) :: term()
  defp schedule_info_flash_clear(socket) do
    _ = Process.send_after(self(), :clear_info_flash, 2_500)
    socket
  end

  @spec sanitize_return_to(term()) :: String.t()
  defp sanitize_return_to(path) when is_binary(path) do
    path = String.trim(path)

    cond do
      path == "" ->
        "/projects"

      path == "/settings" or String.starts_with?(path, "/settings?") ->
        "/projects"

      String.starts_with?(path, "/") and not String.starts_with?(path, "//") ->
        path

      true ->
        "/projects"
    end
  end

  defp sanitize_return_to(_), do: "/projects"
end
