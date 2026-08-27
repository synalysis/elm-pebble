defmodule Elmc.TestSupport.StrictCompileAssertions do
  @moduledoc """
  Shared asserts for plan-primary template gates (compile-once, assert-many).
  """

  alias Elmc.Backend.C.Ast.Lint, as: AstLint
  alias Elmc.Backend.Plan.PrimaryCoverage
  alias Elmc.TestSupport.{GeneratedCTypecheck, TemplateCompile}

  @compile_opts [
    plan_ir_mode: :primary,
    plan_ir_strict: true,
    pebble_int32: true
  ]

  @spec compile_opts() :: keyword()
  def compile_opts, do: @compile_opts

  @spec artifact_dir(String.t()) :: String.t()
  def artifact_dir(template) when is_binary(template) do
    Path.expand("tmp/plan_gate_artifacts/#{template}", Path.dirname(__DIR__))
  end

  @spec compile_template!(String.t(), keyword()) :: map()
  def compile_template!(template, extra \\ []) do
    out_dir = Keyword.get_lazy(extra, :out_dir, fn -> artifact_dir(template) end)

    opts =
      extra
      |> Keyword.drop([:out_dir])
      |> then(&Keyword.merge(@compile_opts, &1))
      |> Keyword.put(:out_dir, out_dir)

    case TemplateCompile.compile_watch_template(template, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "strict template compile failed #{template}: #{inspect(reason)}"
    end
  end

  @spec assert_no_fallbacks!(map()) :: :ok
  def assert_no_fallbacks!(result) do
    fallbacks =
      (result.layout_coercion_diagnostics || [])
      |> Enum.filter(&(&1["code"] == "plan_primary_fallback"))

    unless fallbacks == [] do
      raise ExUnit.AssertionError,
        message: "expected zero plan_primary_fallback, got:\n#{inspect(fallbacks, pretty: true)}"
    end

    :ok
  end

  @spec assert_no_unknown!(String.t()) :: :ok
  def assert_no_unknown!(out_dir) when is_binary(out_dir) do
    c_path = Path.join(out_dir, "c/elmc_generated.c")

    if File.regular?(c_path) do
      unknown_count =
        c_path
        |> File.read!()
        |> then(&Regex.scan(~r/elmc_unknown\b/, &1))
        |> length()

      if unknown_count != 0 do
        raise ExUnit.AssertionError,
          message: "expected zero elmc_unknown in #{c_path}, got #{unknown_count}"
      end
    end

    :ok
  end

  @spec assert_typechecks!(String.t()) :: :ok
  def assert_typechecks!(out_dir), do: GeneratedCTypecheck.assert_typechecks!(out_dir)

  @spec assert_rc_shape!(String.t()) :: :ok
  def assert_rc_shape!(out_dir) do
    c_path = Path.join(out_dir, "c/elmc_generated.c")

    if File.regular?(c_path) do
      AstLint.run_source!(File.read!(c_path))
    end

    :ok
  end

  @spec assert_reachable!(map()) :: :ok
  def assert_reachable!(result) do
    Process.put(:elmc_constructor_tags, Elmc.Backend.CCodegen.IRQueries.constructor_tag_map(result.ir))
    decl_map = TemplateCompile.decl_map_from_result(result)

    reachable =
      PrimaryCoverage.reachable_report(decl_map, ir: result.ir, entry_module: "Main")

    unless reachable.total > 0 and reachable.lowered == reachable.total do
      raise ExUnit.AssertionError,
        message:
          "reachable #{reachable.lowered}/#{reachable.total}: #{inspect(Enum.take(reachable.failed, 8))}"
    end

    :ok
  after
    Process.delete(:elmc_constructor_tags)
  end

  @spec assert_strict_compile!(map(), String.t(), keyword()) :: :ok
  def assert_strict_compile!(result, out_dir, opts \\ []) do
    assert_no_fallbacks!(result)
    assert_no_unknown!(out_dir)
    if Keyword.get(opts, :typecheck, true), do: assert_typechecks!(out_dir)
    if Keyword.get(opts, :rc_shape, true), do: assert_rc_shape!(out_dir)
    if Keyword.get(opts, :reachable, false), do: assert_reachable!(result)
    :ok
  end
end
