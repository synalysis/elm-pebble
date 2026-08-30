defmodule Elmc.WasmWebHtmlTest do
  use ExUnit.Case, async: false

  alias Elmc.TestSupport.CachedCompile
  alias Elmc.Backend.Wasm.ProjectWriter
  alias Elmc.Test.WasmRcTrackHarness

  @html_runner Path.expand("support/wasm_html_probe_runner.mjs", __DIR__)
  @style_runner Path.expand("support/wasm_html_style_probe_runner.mjs", __DIR__)
  @handler_runner Path.expand("support/wasm_html_handler_probe_runner.mjs", __DIR__)

  @tag :wasm_execute
  test "web wasm layout fixture renders header main footer with class and href attrs" do
    run_html_fixture_probe(
      "wasm_web_layout_project",
      "elmc_fn_Main_main",
      "Elm PebbleHello from WASMDocs",
      fn wat ->
        assert wat =~ "html_cmd"
        assert wat =~ "class"
      end,
      fn output ->
        assert output =~ ~s/attrs=[{"name":"class","value":"page"}]/
      end
    )
  end

  @tag :wasm_execute
  test "web wasm Html tag helpers forward attrs and children when called indirectly" do
    run_html_fixture_probe(
      "wasm_web_code_project",
      "elmc_fn_Main_main",
      "ok",
      fn wat ->
        assert wat =~ "html_cmd"
        # `tag = code` forwards as Main.tag(attrs, children) → html_cmd "code"
        assert wat =~ "(func $elmc_fn_Main_tag"
        assert wat =~ "(param $param0 i32) (param $param1 i32)"
      end
    )
  end

  @tag :wasm_execute
  test "web wasm lowers Html.node and Html.map and executes in node" do
    run_html_fixture_probe(
      "wasm_web_node_project",
      "elmc_fn_Main_main",
      "MenuLink mapped",
      fn wat ->
        assert wat =~ "html_cmd"
        assert wat =~ "html_cmd (i32.const 1024) (i32.const 3)"
      end,
      fn output ->
        assert output =~ ~s/attrs=[{"name":"class","value":"page"}]/
      end
    )
  end

  @tag :wasm_execute
  test "web wasm Html.Attributes.style merges CSS properties onto the node" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_html_style_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_html/style", __DIR__)
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
        assert wat =~ "html_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@style_runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "html_style_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Html.Attributes.style probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Html.Attributes.classList joins enabled class names" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_html_class_list_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_html/class_list", __DIR__)
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
        assert wat =~ "html_cmd"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_html_probe(out_dir, "elmc_fn_Main_main", "ok") do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ ~s/"name":"class"/
            assert output =~ ~s/"name":"id"/
            assert output =~ ~s/"name":"title"/
            assert output =~ ~s/"name":"href"/
            assert output =~ ~s/"name":"name"/
            assert output =~ ~s/"name":"placeholder"/
            assert output =~ ~s/"name":"type"/
            assert output =~ ~s/"name":"target"/
            assert output =~ ~s/"name":"rel"/
            assert output =~ ~s/"name":"alt"/
            assert output =~ ~s/"name":"src"/
            assert output =~ ~s/"name":"download"/
            assert output =~ ~s/"name":"action"/
            assert output =~ ~s/"name":"method"/
            assert output =~ ~s/"name":"for"/
            assert output =~ "root"
            assert output =~ "home"
            assert output =~ "https://elm-lang.org"
            assert output =~ "search"
            assert output =~ "_blank"
            assert output =~ "noreferrer"
            assert output =~ "logo"
            assert output =~ "/logo.png"
            assert output =~ "notes.txt"
            assert output =~ "/submit"
            assert output =~ "post"
            assert output =~ "wrap"
            assert output =~ "on also"

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Html.Attributes.classList probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Html.Events preventDefaultOn stopPropagationOn and custom apply Handler flags" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/wasm_web_html_handler_project", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_html/handler", __DIR__)
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
        assert wat =~ "html_cmd"
        assert wat =~ "(i32.const 8)"

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case WasmRcTrackHarness.run_node_script(@handler_runner, [out_dir]) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            assert output =~ "html_handler_ok"

          {:error, output} ->
            if WasmRcTrackHarness.probe_skipped_under_ulimit?(output) or
                 WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm Html.Events Handler probe failed:\n#{output}")
            end
        end
    end
  end

  @tag :wasm_execute
  test "web wasm Html.Attributes bool/string properties keep JS values" do
    run_html_fixture_probe(
      "wasm_web_html_property_project",
      "elmc_fn_Main_main",
      "",
      fn wat ->
        assert wat =~ "html_cmd"
        assert wat =~ "json_encode_bool" or wat =~ "runtime_json_encode_bool"
      end,
      fn output ->
        assert output =~ ~s/"name":"checked","value":true/
        assert output =~ ~s/"name":"disabled","value":false/
        assert output =~ ~s/"name":"hidden","value":true/
        assert output =~ ~s/"name":"value","value":"hi"/
      end
    )
  end

  @tag :wasm_execute
  test "web wasm lowers Html.div to html_cmd node and executes in node" do
    run_html_fixture_probe(
      "wasm_web_div_project",
      "elmc_fn_Main_main",
      "hello world",
      fn wat ->
        assert wat =~ "html_cmd"
        assert wat =~ "list_from_values" or wat =~ "new_immortal_string"
      end
    )
  end

  @tag :wasm_execute
  test "web wasm List.map (Html.map f) renders mapped body items" do
    run_html_fixture_probe(
      "wasm_web_map_list_project",
      "elmc_fn_Main_main",
      "headermainfooter",
      fn wat ->
        assert wat =~ "html_cmd"
        assert wat =~ "list_map"
      end
    )
  end

  @tag :wasm_execute
  test "web wasm preserves hyphenated and breakpoint tailwind class strings" do
    run_html_fixture_probe(
      "wasm_web_tailwind_string_project",
      "elmc_fn_Main_main",
      "ok",
      fn wat -> assert wat =~ "html_cmd" end,
      fn output ->
        assert output =~ ~s/"value":"shrink-0 px-3 p-3 md:px-3 dark:text-gray-700"/
        refute output =~ "shrink - 0"
        refute output =~ ~s/"value":"px-3 px-3/
        refute output =~ ~s/text-gray-50/
        # Tw.p must not resolve to Html.p (would use spacing token as attrs).
        refute output =~ ~s(<p class="3")
      end,
      fn manifest ->
        values =
          case manifest["immortal_strings"] do
            list when is_list(list) -> list
            map when is_map(map) -> Map.values(map)
            _ -> []
          end
        assert "shrink-0" in values
        assert "md:" in values
        assert "dark:" in values
        refute "shrink - 0" in values
      end
    )
  end

  @tag :wasm_execute
  test "web wasm copies browser host entry for manual smoke" do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        out_dir = Path.expand("tmp/wasm_web_html/browser_host", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(Path.expand("fixtures/elm_make_sanity", __DIR__), %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true
                 })

        assert File.regular?(Path.join(out_dir, "host/browser.html"))
        assert File.regular?(Path.join(out_dir, "host/boot.js"))
        assert File.regular?(Path.join(out_dir, "host/page_bytes.js"))
        assert File.regular?(Path.join(out_dir, "host/page_styles.js"))
        assert File.regular?(Path.join(out_dir, "host/json_runtime.js"))
        assert File.regular?(Path.join(out_dir, "host/bytes_runtime.js"))
        assert File.regular?(Path.join(out_dir, "host/rc_runtime.js"))

        boot_js = File.read!(Path.join(out_dir, "host/boot.js"))
        assert boot_js =~ "pageDataFromJs"
        assert boot_js =~ "page_bytes.js"
    end
  end

  @tag :wasm_execute
  test "web wasm lowers VirtualDom.text to html_cmd and executes in node" do
    run_html_fixture_probe(
      "elm_make_sanity",
      "elmc_fn_Main_main",
      "ok",
      fn wat -> assert wat =~ "html_cmd" end
    )
  end

  defp run_html_fixture_probe(
         fixture,
         export,
         expected_text,
         wat_assert,
         output_assert \\ fn _ -> :ok end,
         manifest_assert \\ fn _ -> :ok end
       ) do
    cond do
      not execution_tools_available?() ->
        :ok

      true ->
        root = Path.expand("fixtures/#{fixture}", __DIR__)
        out_dir = Path.expand("tmp/wasm_web_html/#{fixture}", __DIR__)
        File.rm_rf!(out_dir)

        assert {:ok, _} =
                 CachedCompile.compile(root, %{
                   out_dir: out_dir,
                   targets: [:wasm],
                   web: true,
                   entry_module: "Main",
                   strip_dead_code: true
                 })

        manifest = out_dir |> ProjectWriter.manifest_path() |> File.read!() |> Jason.decode!()
        manifest_assert.(manifest)

        refute Enum.any?(ProjectWriter.stub_functions(out_dir), fn stub ->
                 stub["module"] == "Elm.Kernel.VirtualDom" and stub["name"] in ["text", "node"]
               end)

        wat = File.read!(ProjectWriter.wat_path(out_dir))
        wat_assert.(wat)

        WasmRcTrackHarness.run_wat2wasm!(
          ProjectWriter.wat_path(out_dir),
          Path.join(out_dir, "wasm/app.wasm")
        )

        case run_html_probe(out_dir, export, expected_text) do
          {:ok, output} ->
            assert output =~ "rc_ok"
            output_assert.(output)

          {:error, output} ->
            if WasmRcTrackHarness.wasm_instantiate_oom?(output) do
              :ok
            else
              flunk("wasm html probe failed:\n#{output}")
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
