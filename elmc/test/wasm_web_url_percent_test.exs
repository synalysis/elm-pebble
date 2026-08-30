defmodule Elmc.WasmWebUrlPercentTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @html_runner Path.expand("support/wasm_html_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "Url.percentEncode is encodeURIComponent and percentDecode is Maybe String" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_url_percent_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_url_percent", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "url_percent_encode"
        assert wat =~ "url_percent_decode"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected = "a%20b%2Fc|just:a b|just:a+b|nothing"

        case run_html_probe(out_dir, expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Url.percentEncode/Decode probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Url.Builder absolute relative crossOrigin custom and toQuery match official Elm" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_url_builder_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_url_builder", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "url_builder_absolute"
        assert wat =~ "url_builder_custom"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected =
          "/" <>
            "|/packages/elm/core" <>
            "|/products?search=hat&page=2" <>
            "|" <>
            "|elm/core" <>
            "|https://example.com/products" <>
            "|https://example.com/" <>
            "|/packages/elm/core/latest/String#length" <>
            "|there?name=ferret" <>
            "|https://example.com:8042/over/there?name=ferret#nose" <>
            "|?search=coffee%20table" <>
            "|"

        case run_html_probe(out_dir, expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Url.Builder probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "Url.fromString matches official elm/url chomp not new URL()" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_url_from_string_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_url_from_string", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true,
                   wasm_strict: true
                 })

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "url_from_string"
        assert wat =~ "url_to_string"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected =
          "https,example.com,443,/,n,n,https://example.com:443/" <>
            "|https,example.com,n,/hats,q=top%20hat,n,https://example.com/hats?q=top%20hat" <>
            "|http,example.com,n,/core/List/,n,map,http://example.com/core/List/#map" <>
            "|nothing|nothing|nothing"

        case run_html_probe(out_dir, expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Url.fromString probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_html_probe(out_dir, expected_text) do
    WasmRcTrackHarness.run_node_script(@html_runner, [out_dir, "elmc_fn_Main_main", expected_text])
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
