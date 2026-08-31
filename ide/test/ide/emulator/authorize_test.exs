defmodule Ide.Emulator.AuthorizeTest do
  use ExUnit.Case, async: false

  alias Ide.Emulator

  setup do
    original = Application.get_env(:ide, Ide.Auth, [])
    on_exit(fn -> Application.put_env(:ide, Ide.Auth, original) end)
    :ok
  end

  test "local mode authorizes any lookup" do
    Application.put_env(
      :ide,
      Ide.Auth,
      Keyword.put(Application.get_env(:ide, Ide.Auth, []), :mode, :local)
    )
    id = "local-auth-#{System.unique_integer([:positive])}"
    pid = register_session(id, %{owner_id: 1})

    try do
      assert {:ok, ^pid} = Emulator.authorize(id, nil)
      assert {:ok, ^pid} = Emulator.authorize(id, %{id: 2})
    after
      Process.exit(pid, :kill)
    end
  end

  test "public mode hides sessions owned by another user" do
    Application.put_env(
      :ide,
      Ide.Auth,
      Keyword.put(Application.get_env(:ide, Ide.Auth, []), :mode, :public_pebble)
    )
    id = "public-auth-#{System.unique_integer([:positive])}"
    pid = register_session(id, %{owner_id: 41})

    try do
      assert {:error, :not_found} = Emulator.authorize(id, nil)
      assert {:error, :not_found} = Emulator.authorize(id, %{id: 42})
      assert {:ok, ^pid} = Emulator.authorize(id, %{id: 41})
    after
      Process.exit(pid, :kill)
    end
  end

  defp register_session(id, meta) do
    parent = self()

    pid =
      spawn(fn ->
        {:ok, _} = Registry.register(Ide.Emulator.Registry, id, meta)
        send(parent, :registered)
        Process.sleep(:infinity)
      end)

    assert_receive :registered
    pid
  end
end
