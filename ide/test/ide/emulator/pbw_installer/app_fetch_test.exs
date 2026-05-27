defmodule Ide.Emulator.PBWInstaller.AppFetchTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.PBWInstaller.AppFetch

  test "verify_fetch_uuid/2 accepts matching uuids" do
    uuid = "00000000-0000-4000-8000-000000000001"
    assert :ok = AppFetch.verify_fetch_uuid(uuid, uuid)
  end

  test "verify_fetch_uuid/2 rejects mismatched uuids" do
    assert {:error, {:wrong_app_fetch_uuid, "expected", "actual"}} =
             AppFetch.verify_fetch_uuid("actual", "expected")
  end
end
