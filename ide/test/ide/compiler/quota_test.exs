defmodule Ide.Compiler.QuotaTest do
  use ExUnit.Case, async: false

  alias Ide.Compiler.Quota

  setup do
    original = Application.get_env(:ide, Ide.Auth, [])

    on_exit(fn ->
      Application.put_env(:ide, Ide.Auth, original)
      Process.delete(:ide_current_user)
    end)

    :ok
  end

  test "local mode does not cap concurrent compiles" do
    Application.put_env(
      :ide,
      Ide.Auth,
      Keyword.put(Application.get_env(:ide, Ide.Auth, []), :mode, :local)
    )
    Process.put(:ide_current_user, %{id: 7})

    assert :ok = Quota.checkout()
    assert :ok = Quota.checkout()
    assert :ok = Quota.checkout()
  end

  test "public mode caps concurrent compiles per user" do
    Application.put_env(
      :ide,
      Ide.Auth,
      Keyword.put(Application.get_env(:ide, Ide.Auth, []), :mode, :public_pebble)
    )
    alice = System.unique_integer([:positive])
    bob = System.unique_integer([:positive])
    Process.put(:ide_current_user, %{id: alice})

    assert :ok = Quota.checkout()
    assert :ok = Quota.checkout()
    assert {:error, :busy} = Quota.checkout()

    assert {:error, :busy} =
             Quota.with_quota(fn ->
               flunk("quota should not run the job")
             end)

    Process.put(:ide_current_user, %{id: bob})
    assert :ok = Quota.checkout()

    assert :ok = Quota.checkin()
    Process.put(:ide_current_user, %{id: alice})
    assert :ok = Quota.checkin()
    assert :ok = Quota.checkin()
  end
end
