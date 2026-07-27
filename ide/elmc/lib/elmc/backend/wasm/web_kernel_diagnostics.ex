defmodule Elmc.Backend.Wasm.WebKernelDiagnostics do
  @moduledoc false

  alias Elmc.Backend.Plan.Lower.Platform.Web, as: PlatformWeb

  @cache_fields ~w(cacheStrategy cachePath)
  @just_names ~w(Just Maybe.Just)

  @spec maybe_warn_browser_cache_options(term()) :: :ok
  def maybe_warn_browser_cache_options(options) do
    if PlatformWeb.web_target?(Process.get(:elmc_codegen_opts, %{})) and
         cache_field_just?(options) do
      append_diagnostic(%{
        source: "elmc/web",
        code: "browser_http_cache_ignored",
        message:
          "BackendTask.Http cacheStrategy/cachePath are ignored in browser WASM builds; requests use fetch directly without the Node HTTP cache."
      })
    end

    :ok
  end

  @spec compile_diagnostics() :: [map()]
  def compile_diagnostics do
    Process.get(:elmc_web_kernel_diagnostics, %{})
    |> Map.values()
    |> Enum.map(fn warning ->
      %{
        "source" => warning.source,
        "code" => warning.code,
        "severity" => "warning",
        "message" => warning.message
      }
    end)
  end

  @spec append_diagnostic(map()) :: :ok
  def append_diagnostic(%{source: source, code: code, message: message}) do
    cache = Process.get(:elmc_web_kernel_diagnostics, %{})

    if Map.has_key?(cache, code) do
      :ok
    else
      Process.put(:elmc_web_kernel_diagnostics, Map.put(cache, code, %{source: source, code: code, message: message}))
      :ok
    end
  end

  @spec cache_field_just?(map() | term()) :: boolean()

  defp cache_field_just?(%{op: :record_literal, fields: fields}) when is_list(fields) do
    Enum.any?(fields, fn
      %{name: name, expr: expr} when name in @cache_fields -> maybe_just?(expr)
      _ -> false
    end)
  end

  defp cache_field_just?(_), do: false

  @spec maybe_just?(map() | term()) :: boolean()

  defp maybe_just?(%{op: :tuple2, left: %{union_ctor: ctor}}) when ctor in @just_names, do: true
  defp maybe_just?(%{union_ctor: ctor}) when ctor in @just_names, do: true

  defp maybe_just?(%{op: :constructor_call, target: target}) when target in @just_names,
    do: true

  defp maybe_just?(_), do: false
end
