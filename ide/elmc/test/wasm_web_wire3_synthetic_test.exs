defmodule Elmc.WasmWebWire3SyntheticTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Wasm.ProjectWriter

  test "synthetic wire3 defaults only fill missing UrlPath and NotFoundReason decoders" do
    existing_decoder = %{
      kind: :function,
      name: "w3_decode_PageData",
      args: [],
      type: nil,
      expr: %{op: :var, name: "real_codec"}
    }

    decl_map = %{
      {"Main", "w3_decode_PageData"} => existing_decoder,
      {"Pages.Internal.ResponseSketch", "w3_decode_ResponseSketch"} => existing_decoder,
      {"UrlPath", "w3_encode_UrlPath"} => %{kind: :function}
    }

    synthetics = ProjectWriter.web_wire3_synthetic_decls_for_test(decl_map)

    refute Enum.any?(synthetics, fn {module, name, _} ->
             module == "Main" and name == "w3_decode_PageData"
           end)

    refute Enum.any?(synthetics, fn {module, name, _} ->
             module == "Pages.Internal.ResponseSketch" and name == "w3_decode_ResponseSketch"
           end)

    assert {"UrlPath", "w3_decode_UrlPath", _} = List.keyfind(synthetics, "UrlPath", 0)

    assert {"Pages.Internal.NotFoundReason", "w3_decode_NotFoundReason", _} =
             List.keyfind(synthetics, "Pages.Internal.NotFoundReason", 0)
  end

  test "synthetic wire3 defaults are omitted when UrlPath and NotFoundReason already exist" do
    decl_map = %{
      {"UrlPath", "w3_decode_UrlPath"} => %{kind: :function},
      {"Pages.Internal.NotFoundReason", "w3_decode_NotFoundReason"} => %{kind: :function},
      {"Main", "w3_decode_PageData"} => %{kind: :function}
    }

    assert ProjectWriter.web_wire3_synthetic_decls_for_test(decl_map) == []
  end
end
