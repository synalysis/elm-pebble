defmodule Ide.SettingsTest do
  use ExUnit.Case, async: true

  alias Ide.Settings

  test "defaults to regular editor mode and persists updates" do
    temp_path =
      Path.join(System.tmp_dir!(), "ide_settings_test_#{System.unique_integer([:positive])}.json")

    original_config = Application.get_env(:ide, Ide.Settings, [])
    Application.put_env(:ide, Ide.Settings, settings_path: temp_path)

    on_exit(fn ->
      Application.put_env(:ide, Ide.Settings, original_config)
      File.rm(temp_path)
    end)

    assert %{auto_format_on_save: false, editor_mode: :regular, formatter_backend: :elm_format} =
             Settings.current()

    assert :ok = Settings.set_auto_format_on_save(true)
    assert :ok = Settings.set_formatter_backend("elm_format")
    assert :ok = Settings.set_editor_mode("vim")

    assert %{auto_format_on_save: true, editor_mode: :vim, formatter_backend: :elm_format} =
             Settings.current()
  end

  test "rejects unknown editor mode values" do
    temp_path =
      Path.join(System.tmp_dir!(), "ide_settings_test_#{System.unique_integer([:positive])}.json")

    original_config = Application.get_env(:ide, Ide.Settings, [])
    Application.put_env(:ide, Ide.Settings, settings_path: temp_path)

    on_exit(fn ->
      Application.put_env(:ide, Ide.Settings, original_config)
      File.rm(temp_path)
    end)

    assert {:error, {:invalid_editor_mode, "emacs"}} = Settings.set_editor_mode("emacs")
    assert %{editor_mode: :regular} = Settings.current()
  end

  test "rejects unknown formatter backend values" do
    temp_path =
      Path.join(System.tmp_dir!(), "ide_settings_test_#{System.unique_integer([:positive])}.json")

    original_config = Application.get_env(:ide, Ide.Settings, [])
    Application.put_env(:ide, Ide.Settings, settings_path: temp_path)

    on_exit(fn ->
      Application.put_env(:ide, Ide.Settings, original_config)
      File.rm(temp_path)
    end)

    assert {:error, {:invalid_formatter_backend, "pretty"}} =
             Settings.set_formatter_backend("pretty")

    assert %{formatter_backend: :elm_format} = Settings.current()
  end

  test "persists MCP and ACP access settings" do
    temp_path =
      Path.join(System.tmp_dir!(), "ide_settings_test_#{System.unique_integer([:positive])}.json")

    original_config = Application.get_env(:ide, Ide.Settings, [])
    Application.put_env(:ide, Ide.Settings, settings_path: temp_path)

    on_exit(fn ->
      Application.put_env(:ide, Ide.Settings, original_config)
      File.rm(temp_path)
    end)

    assert %{
             mcp_http_enabled: true,
             mcp_http_port: 4000,
             mcp_http_capabilities: [:read],
             acp_agent_enabled: true,
             acp_agent_capabilities: [:read]
           } = Settings.current()

    assert :ok = Settings.set_mcp_http_enabled(false)
    assert :ok = Settings.set_mcp_http_port("4100")
    assert :ok = Settings.set_mcp_http_capabilities(["read", "edit", "unknown"])
    assert :ok = Settings.set_acp_agent_enabled(false)
    assert :ok = Settings.set_acp_agent_capabilities("read,build")

    assert %{
             mcp_http_enabled: false,
             mcp_http_port: 4100,
             mcp_http_capabilities: [:read, :edit],
             acp_agent_enabled: false,
             acp_agent_capabilities: [:read, :build]
           } = Settings.current()
  end

  test "rejects invalid MCP HTTP ports" do
    temp_path =
      Path.join(System.tmp_dir!(), "ide_settings_test_#{System.unique_integer([:positive])}.json")

    original_config = Application.get_env(:ide, Ide.Settings, [])
    Application.put_env(:ide, Ide.Settings, settings_path: temp_path)

    on_exit(fn ->
      Application.put_env(:ide, Ide.Settings, original_config)
      File.rm(temp_path)
    end)

    assert {:error, {:invalid_port, "70000"}} = Settings.set_mcp_http_port("70000")
    assert %{mcp_http_port: 4000} = Settings.current()
  end
end
