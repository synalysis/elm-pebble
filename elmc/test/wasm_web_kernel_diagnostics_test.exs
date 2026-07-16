defmodule Elmc.Backend.Wasm.WebKernelDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Wasm.WebKernelDiagnostics

  setup do
    on_exit(fn -> Process.delete(:elmc_web_kernel_diagnostics) end)
    :ok
  end

  test "detects cacheStrategy Just in getWithOptions record literal" do
    options = %{
      op: :record_literal,
      fields: [
        %{name: "url", expr: %{op: :string_literal, value: "https://example.com"}},
        %{name: "expect", expr: %{op: :int_literal, value: 0}},
        %{name: "headers", expr: %{op: :list_literal, items: []}},
        %{
          name: "cacheStrategy",
          expr: %{
            op: :tuple2,
            left: %{op: :int_literal, value: 1, union_ctor: "Maybe.Just"},
            right: %{op: :int_literal, value: 0}
          }
        }
      ]
    }

    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    assert :ok = WebKernelDiagnostics.maybe_warn_browser_cache_options(options)

    assert [%{"code" => "browser_http_cache_ignored", "severity" => "warning"}] =
             WebKernelDiagnostics.compile_diagnostics()
  end

  test "does not warn when cacheStrategy is Nothing" do
    options = %{
      op: :record_literal,
      fields: [
        %{
          name: "cacheStrategy",
          expr: %{op: :int_literal, value: 0, union_ctor: "Maybe.Nothing"}
        }
      ]
    }

    Process.put(:elmc_codegen_opts, %{web: true, targets: [:wasm]})

    assert :ok = WebKernelDiagnostics.maybe_warn_browser_cache_options(options)
    assert WebKernelDiagnostics.compile_diagnostics() == []
  end
end
