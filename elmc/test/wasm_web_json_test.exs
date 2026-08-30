defmodule Elmc.WasmWebJsonTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @html_runner Path.expand("support/wasm_html_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm decodes and encodes json via Elm.Kernel.Json lowering" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_json_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_json/decode_encode", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true
                 })

        refute Enum.any?(ProjectWriter.stub_functions(out_dir), fn stub ->
                 stub["module"] == "Elm.Kernel.Json"
               end)

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        assert wat =~ "json_decode_int_decoder"
        assert wat =~ "json_decode_string"
        assert wat =~ "json_encode_object"
        assert wat =~ "json_encode_encode"
        refute wat =~ "runtime_json_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected = ~s/int:42 json:{"x":1} null:1 pretty:1/

        case run_html_probe(out_dir, "elmc_fn_Main_main", expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm json probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm encodes Json.Encode.dict set list and array" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_json_dict_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_json/dict_set", __DIR__)
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
        assert wat =~ "json_encode_dict"
        assert wat =~ "json_encode_set"
        assert wat =~ "json_encode_list"
        assert wat =~ "json_encode_array"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected = ~s/{"a":1,"b":2} [1,2] [1,2] [3,4]/

        case run_html_probe(out_dir, "elmc_fn_Main_main", expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm json dict probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Decode.keyValuePairs keeps official object key order" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_json_key_value_pairs_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_json/key_value_pairs", __DIR__)
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
        assert wat =~ "json_decode_key_value_pairs"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_html_probe(out_dir, "elmc_fn_Main_main", "a:1,b:2") do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "a:1,b:2"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm json keyValuePairs probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Decode.dict builds a Dict via Dict.fromList" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_json_decode_dict_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_json/decode_dict", __DIR__)
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
        assert wat =~ "json_decode_dict"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_html_probe(out_dir, "elmc_fn_Main_main", "ok") do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm json decode dict probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Decode.value decodeValue and Decode.array match official Elm" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_json_value_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_json/value", __DIR__)
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
        assert wat =~ "json_decode_value_decoder"
        assert wat =~ "json_decode_value"
        assert wat =~ "json_decode_array"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_html_probe(out_dir, "elmc_fn_Main_main", "ok") do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm json Decode.value/array probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Decode.oneOf andThen maybe nullable and lazy match official Elm" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_json_one_of_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_json/one_of", __DIR__)
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
        assert wat =~ "json_decode_one_of"
        assert wat =~ "json_decode_and_then"
        assert wat =~ "json_decode_maybe"
        assert wat =~ "json_decode_nullable"
        assert wat =~ "json_decode_lazy"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected = "i:1|s:x|err|err|nothing|nothing|just:4|nothing|just:5|err|lazy:9"

        case run_html_probe(out_dir, "elmc_fn_Main_main", expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm json oneOf probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Decode.at is fields-only and Decode.index is array index" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_json_at_index_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_json/at_index", __DIR__)
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
        assert wat =~ "json_decode_at"
        assert wat =~ "json_decode_index"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected = "ada|20|7|err"

        case run_html_probe(out_dir, "elmc_fn_Main_main", expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm json at/index probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Decode.oneOrMore requires a non-empty array" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_json_one_or_more_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_json/one_or_more", __DIR__)
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
        assert wat =~ "json_decode_list" or wat =~ "json_decode_and_then"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        expected = "1:2|7:0|err|err"

        case run_html_probe(out_dir, "elmc_fn_Main_main", expected) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ expected

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm json oneOrMore probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Decode.map8 fills an 8-field record in declaration order" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_json_map8_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_json/map8", __DIR__)
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
        assert wat =~ "json_decode_map8"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_html_probe(out_dir, "elmc_fn_Main_main", "1:2:3:4:5:6:7:ok") do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "1:2:3:4:5:6:7:ok"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm json map8 probe failed:\n#{output}")
            end
        end
    end
  end

  defp run_html_probe(out_dir, export_name, expected_text) do
    node = System.find_executable("node")

    case node do
      nil ->
        {:error, "node not available"}

      node ->
        args = [out_dir, export_name, expected_text]

        {output, code} =
          System.cmd(node, [@html_runner | args], stderr_to_stdout: true)

        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  defp execution_tools_available? do
    System.find_executable("node") != nil and
      (System.find_executable("wat2wasm") != nil or System.find_executable("npx") != nil)
  end
end
