defmodule IdeWeb.SettingsLiveTest do
  use IdeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ide.Settings

  setup do
    temp_path =
      Path.join(
        System.tmp_dir!(),
        "ide_settings_live_test_#{System.unique_integer([:positive])}.json"
      )

    original_config = Application.get_env(:ide, Ide.Settings, [])
    Application.put_env(:ide, Ide.Settings, settings_path: temp_path)

    on_exit(fn ->
      Application.put_env(:ide, Ide.Settings, original_config)
      File.rm(temp_path)
    end)

    :ok
  end

  test "settings page persists editor mode", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, ~p"/settings")
    assert render(view) =~ "Editor mode"
    assert render(view) =~ "Built-in formatter (experimental)"
    assert render(view) =~ ~r/<option[^>]*value="elm_format"[^>]*selected/

    view
    |> form("form", %{
      "settings" => %{
        "auto_format_on_save" => "true",
        "debug_mode" => "true",
        "formatter_backend" => "elm_format",
        "editor_mode" => "vim",
        "editor_theme" => "dark",
        "editor_line_numbers" => "true",
        "editor_active_line_highlight" => "true",
        "mcp_http_enabled" => "true",
        "mcp_http_port" => "4100",
        "mcp_http_capabilities" => ["read", "edit"],
        "acp_agent_enabled" => "true",
        "acp_agent_capabilities" => ["read", "build"]
      }
    })
    |> render_submit()

    assert render(view) =~ "Settings saved."

    assert %{
             editor_mode: :vim,
             auto_format_on_save: true,
             debug_mode: true,
             formatter_backend: :elm_format,
             editor_theme: :dark,
             editor_line_numbers: true,
             editor_active_line_highlight: true,
             mcp_http_enabled: true,
             mcp_http_port: 4100,
             mcp_http_capabilities: [:read, :edit],
             acp_agent_enabled: true,
             acp_agent_capabilities: [:read, :build]
           } = Settings.current()

    assert render(view) =~ ~r/<option[^>]*value="vim"[^>]*selected/
    assert render(view) =~ ~r/<option[^>]*value="elm_format"[^>]*selected/
    assert render(view) =~ ~r/<option[^>]*value="dark"[^>]*selected/
    html = render(view)
    assert html =~ "MCP / ACP access"
    assert html =~ "Editor configuration snippets"
    assert html =~ "Client / editor"
    assert html =~ "Generic MCP client (remote URL)"
    assert html =~ "Generic MCP client (local stdio)"
    assert html =~ "Generic ACP client (local stdio agent)"
    assert html =~ "Zed (remote MCP context server)"
    assert html =~ "Zed (local ACP external agent)"
    assert html =~ "Cursor / Claude Desktop style (local MCP stdio)"
    assert html =~ "http://localhost:4100/api/mcp"
    assert html =~ "mcpServers"
    assert html =~ "url"

    view
    |> element("select[name='snippet_target']")
    |> render_change(%{"snippet_target" => "zed_stdio_acp"})

    html = render(view)
    assert html =~ "Zed local ACP external agent"
    assert html =~ "agent_servers"
    assert html =~ "mix ide.acp_agent --capabilities"
    assert html =~ "read,build"

    view
    |> element("select[name='snippet_target']")
    |> render_change(%{"snippet_target" => "generic_stdio_acp"})

    html = render(view)
    assert html =~ "Generic ACP client (local stdio agent)"
    assert html =~ "command"
    assert html =~ "args"
    assert html =~ "mix ide.acp_agent --capabilities"
    refute html =~ ~s(bash -lc 'cd '"'"')

    view
    |> element("select[name='snippet_target']")
    |> render_change(%{"snippet_target" => "generic_stdio_mcp"})

    html = render(view)
    assert html =~ "Generic MCP client (local stdio)"
    assert html =~ "mix ide.mcp --capabilities"
    assert html =~ "read,edit"
    assert html =~ ~s(phx-hook="CopyToClipboard")
  end

  test "emulator dependency install button is disabled while install is running", %{conn: conn} do
    previous_session_config = Application.get_env(:ide, Ide.Emulator.Session)
    previous_path = System.get_env("PATH")

    root =
      Path.join(
        System.tmp_dir!(),
        "ide_settings_install_button_test_#{System.unique_integer([:positive])}"
      )

    bin_dir = Path.join(root, "bin")
    uv_bin = Path.join(bin_dir, "uv")

    File.mkdir_p!(bin_dir)

    File.write!(uv_bin, """
    #!/bin/sh
    sleep 1
    exit 0
    """)

    File.chmod!(uv_bin, 0o755)

    Application.put_env(:ide, Ide.Emulator.Session,
      enabled: true,
      sdk_roots: [],
      qemu_image_root: Path.join(root, "images"),
      pebble_tool_python: "3.13"
    )

    path = if previous_path in [nil, ""], do: bin_dir, else: "#{bin_dir}:#{previous_path}"

    System.put_env("PATH", path)

    try do
      assert {:ok, view, _html} = live(conn, ~p"/settings")

      html = render_click(view, "install-emulator-dependencies")

      assert html =~ "Installing..."
      assert html =~ ~s(phx-disable-with="Installing...")

      assert html =~
               ~r/<button(?=[^>]*phx-click="install-emulator-dependencies")(?=[^>]*disabled)[^>]*>.*Installing/s
    after
      Application.put_env(:ide, Ide.Emulator.Session, previous_session_config)
      restore_env("PATH", previous_path)
      File.rm_rf!(root)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
