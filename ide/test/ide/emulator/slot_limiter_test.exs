defmodule Ide.Emulator.SlotLimiterTest do
  use ExUnit.Case, async: false

  alias Ide.Emulator.SlotLimiter

  setup do
    # SlotLimiter is a named singleton; tests run sequentially (async: false).
    Enum.each(SlotLimiter.status().slots, fn %{owner: owner} ->
      SlotLimiter.release(owner)
    end)

    :ok
  end

  test "defaults to eight slots from application config" do
    assert %{max_slots: 8} = SlotLimiter.status()
  end

  test "acquire and release embedded slots" do
    assert {:ok, "session-a"} =
             SlotLimiter.acquire("session-a", kind: :embedded, platform: "basalt")

    assert %{used_slots: 1} = SlotLimiter.status()
    SlotLimiter.release("session-a")
    assert %{used_slots: 0} = SlotLimiter.status()
  end

  test "embedded and external slots share the same pool" do
    owners =
      for index <- 1..7 do
        owner = "embedded-#{index}"
        assert {:ok, ^owner} = SlotLimiter.acquire(owner, kind: :embedded)
        owner
      end

    assert {:ok, "external-basalt"} =
             SlotLimiter.acquire("external-basalt", kind: :external, platform: "basalt")

    assert %{used_slots: 8, available_slots: 0} = SlotLimiter.status()

    assert {:error, :timeout} =
             SlotLimiter.acquire("session-blocked", kind: :embedded, timeout: 50)

    SlotLimiter.release("external-basalt")

    assert {:ok, "session-blocked"} =
             SlotLimiter.acquire("session-blocked", kind: :embedded, timeout: 200)

    Enum.each(owners, &SlotLimiter.release/1)
    SlotLimiter.release("session-blocked")
  end

  test "release_all_external frees only external slots" do
    assert {:ok, _} = SlotLimiter.acquire("embedded-1", kind: :embedded)
    assert {:ok, _} = SlotLimiter.acquire("external-chalk", kind: :external, platform: "chalk")

    SlotLimiter.release_all_external()

    assert %{used_slots: 1, slots: slots} = SlotLimiter.status()
    assert [%{owner: "embedded-1", kind: :embedded}] = slots

    SlotLimiter.release("embedded-1")
  end

  test "re-acquiring the same owner is idempotent" do
    assert {:ok, "session-a"} = SlotLimiter.acquire("session-a", kind: :embedded, timeout: 100)
    assert {:ok, "session-a"} = SlotLimiter.acquire("session-a", kind: :embedded, timeout: 100)
    assert %{used_slots: 1} = SlotLimiter.status()
    SlotLimiter.release("session-a")
  end

  test "public mode caps slots per tenant without blocking other tenants" do
    original = Application.get_env(:ide, Ide.Auth, [])
    Application.put_env(:ide, Ide.Auth, Keyword.put(original, :mode, :public_pebble))

    on_exit(fn ->
      Application.put_env(:ide, Ide.Auth, original)
    end)

    assert {:ok, "alice-a"} =
             SlotLimiter.acquire("alice-a", kind: :embedded, tenant_id: 11, timeout: 50)

    assert {:ok, "alice-b"} =
             SlotLimiter.acquire("alice-b", kind: :embedded, tenant_id: 11, timeout: 50)

    assert {:error, :timeout} =
             SlotLimiter.acquire("alice-c", kind: :embedded, tenant_id: 11, timeout: 50)

    assert {:ok, "bob-a"} =
             SlotLimiter.acquire("bob-a", kind: :embedded, tenant_id: 12, timeout: 50)

    SlotLimiter.release("alice-a")
    SlotLimiter.release("alice-b")
    SlotLimiter.release("bob-a")
  end
end
