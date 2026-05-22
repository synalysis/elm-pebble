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

  test "public mode stores settings per user" do
    data_root = Path.join(System.tmp_dir!(), "ide_settings_users_#{System.unique_integer([:positive])}")

    original_config = Application.get_env(:ide, Ide.Settings, [])
    original_auth = Application.get_env(:ide, Ide.Auth, [])

    Application.put_env(:ide, Ide.Settings, data_root: data_root)
    Application.put_env(:ide, Ide.Auth, mode: :public_custom)

    on_exit(fn ->
      Application.put_env(:ide, Ide.Settings, original_config)
      Application.put_env(:ide, Ide.Auth, original_auth)
      File.rm_rf(data_root)
      Process.delete(:ide_current_user)
    end)

    alice = %{id: 1}
    bob = %{id: 2}

    Process.put(:ide_current_user, alice)
    assert :ok = Settings.set_editor_mode("vim")
    assert %{editor_mode: :vim} = Settings.current()

    Process.put(:ide_current_user, bob)
    assert %{editor_mode: :regular} = Settings.current()

    Process.put(:ide_current_user, alice)
    assert %{editor_mode: :vim} = Settings.current()

    assert File.exists?(Path.join(data_root, "users/1/settings.json"))
    refute File.exists?(Path.join(data_root, "users/2/settings.json"))
  end

  test "public auth mode forces MCP and ACP settings off" do
    temp_path =
      Path.join(System.tmp_dir!(), "ide_settings_test_#{System.unique_integer([:positive])}.json")

    original_config = Application.get_env(:ide, Ide.Settings, [])
    original_auth = Application.get_env(:ide, Ide.Auth, [])

    Application.put_env(:ide, Ide.Settings, settings_path: temp_path)
    Application.put_env(:ide, Ide.Auth, mode: :public_custom)

    on_exit(fn ->
      Application.put_env(:ide, Ide.Settings, original_config)
      Application.put_env(:ide, Ide.Auth, original_auth)
      File.rm(temp_path)
    end)

    File.write!(
      temp_path,
      Jason.encode!(%{
        "mcp_http_enabled" => true,
        "acp_agent_enabled" => true
      })
    )

    assert %{mcp_http_enabled: false, acp_agent_enabled: false} = Settings.current()
    assert :ok = Settings.set_mcp_http_enabled(true)
    assert :ok = Settings.set_acp_agent_enabled(true)
    assert %{mcp_http_enabled: false, acp_agent_enabled: false} = Settings.current()
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
