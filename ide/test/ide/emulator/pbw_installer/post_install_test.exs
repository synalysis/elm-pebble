defmodule Ide.Emulator.PBWInstaller.PostInstallTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.PBWInstaller.PostInstall

  test "enrich_observed_frame/2 adds data logging tag hex for app message payloads" do
    tag = 0x1234ABCD
    payload = <<1, 0, 0::128, 0::32-little, tag::32-little>>

    observed = %{endpoint: 0xBADA, payload_bytes: byte_size(payload)}

    enriched = PostInstall.enrich_observed_frame(observed, payload)

    assert enriched.data_logging_tag_hex == "0x1234ABCD"
  end

  test "enrich_observed_frame/2 leaves observed unchanged for other payloads" do
    observed = %{endpoint: 1, payload_bytes: 4}
    assert PostInstall.enrich_observed_frame(observed, <<0, 1, 2, 3>>) == observed
  end
end
