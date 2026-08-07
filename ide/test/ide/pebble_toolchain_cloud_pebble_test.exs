defmodule Ide.PebbleToolchain.CloudPebbleTest do
  use ExUnit.Case, async: false

  alias Ide.PebbleToolchain

  test "install_cloudpebble runs pebble install --cloudpebble with isolated credential home" do
    root = Path.join(System.tmp_dir!(), "ide_cloudpebble_test_#{System.unique_integer([:positive])}")
    pbw = Path.join(root, "demo.pbw")
    log_path = Path.join(root, "pebble_invocation.log")
    pebble_bin = Path.join(root, "pebble")

    File.mkdir_p!(root)
    File.write!(pbw, "pbw")

    File.write!(pebble_bin, """
    #!/bin/sh
    {
      echo "HOME=$HOME"
      echo "XDG_DATA_HOME=$XDG_DATA_HOME"
      CRED="$XDG_DATA_HOME/pebble-sdk/oauth_firebase/firebase_oauth_storage.json"
      if [ -f "$CRED" ]; then
        echo "CRED_EXISTS=yes"
        cat "$CRED"
      else
        echo "CRED_EXISTS=no"
      fi
      printf '%s\\n' "$@"
    } >> "#{log_path}"
    exit 0
    """)

    File.chmod!(pebble_bin, 0o755)

    original = Application.get_env(:ide, Ide.PebbleToolchain, [])
    Application.put_env(:ide, Ide.PebbleToolchain, Keyword.put(original, :pebble_bin, pebble_bin))

    on_exit(fn ->
      Application.put_env(:ide, Ide.PebbleToolchain, original)
      File.rm_rf(root)
    end)

    assert {:ok, result} =
             PebbleToolchain.install_cloudpebble("demo",
               package_path: pbw,
               firebase_id_token: "firebase-token-123"
             )

    assert result.status == :ok
    log = File.read!(log_path)
    assert log =~ "install"
    assert log =~ "--cloudpebble"
    assert log =~ pbw
    assert log =~ "CRED_EXISTS=yes"
    assert log =~ "firebase-token-123"
    assert log =~ "XDG_DATA_HOME="

    credential_home =
      log
      |> String.split("\n")
      |> Enum.find_value(fn line ->
        case String.split(line, "=", parts: 2) do
          ["HOME", home] -> home
          _ -> nil
        end
      end)

    assert is_binary(credential_home)
    assert credential_home != ""
    refute File.exists?(credential_home)
  end

  test "install_cloudpebble rejects missing firebase token" do
    assert {:error, :firebase_id_token_required} =
             PebbleToolchain.install_cloudpebble("demo",
               package_path: "/tmp/demo.pbw",
               firebase_id_token: ""
             )
  end

  test "install_cloudpebble rejects missing pbw" do
    assert {:error, :pbw_not_found} =
             PebbleToolchain.install_cloudpebble("demo",
               package_path: "/nonexistent/demo.pbw",
               firebase_id_token: "token"
             )
  end
end
