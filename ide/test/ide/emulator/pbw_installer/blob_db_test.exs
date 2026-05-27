defmodule Ide.Emulator.PBWInstaller.BlobDbTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.PBWInstaller.BlobDb

  test "verify_blob_response/2 accepts success with matching token" do
    assert :ok = BlobDb.verify_blob_response(%{success?: true, token: 42}, 42)
  end

  test "verify_blob_response/2 rejects token mismatch" do
    assert {:error, {:wrong_blob_token, 1, 2}} =
             BlobDb.verify_blob_response(%{token: 2}, 1)
  end

  test "verify_blob_response/2 maps failure response to blob_insert_failed" do
    assert {:error, {:blob_insert_failed, 7}} =
             BlobDb.verify_blob_response(%{response: 7}, 1)
  end
end
