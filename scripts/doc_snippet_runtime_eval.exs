#!/usr/bin/env elixir

defmodule DocSnippetRuntimeEval do
  @moduledoc false

  def main(argv) do
    opts = parse_args(argv)
    engine = Map.get(opts, "engine")
    project_dir = Map.get(opts, "project")
    out_dir = Map.get(opts, "out-dir", "/tmp/doc_snippet_runtime_eval")
    module_name = Map.get(opts, "module", "DocTests.Generated")
    function_prefix = Map.get(opts, "function-prefix", "docTest")
    eval_timeout_ms = parse_int(Map.get(opts, "eval-timeout-ms"), 2_000)

    result =
      cond do
        not is_binary(engine) ->
          %{status: "error", error: "missing --engine"}

        not is_binary(project_dir) ->
          %{status: "error", error: "missing --project"}

        engine not in ["elmc", "elm_executor"] ->
          %{status: "error", error: "invalid --engine (expected elmc|elm_executor)"}

        true ->
          run(engine, project_dir, out_dir, module_name, function_prefix, eval_timeout_ms)
      end

    IO.puts(Jason.encode!(result))
  end

  defp run("elmc", project_dir, out_dir, module_name, function_prefix, eval_timeout_ms) do
    evaluator_path =
      Path.expand("../elm_executor/lib/elm_executor/runtime/core_ir_evaluator.ex", __DIR__)

    if File.exists?(evaluator_path) do
      Code.require_file(evaluator_path)
    end

    case Elmc.compile(project_dir, %{out_dir: out_dir, runtime_dir: Path.join(out_dir, "runtime"), strip_dead_code: false}) do
      {:ok, %{ir: ir}} ->
        case ElmEx.CoreIR.from_ir(ir, strict?: false) do
          {:ok, core_ir} ->
            eval_core_ir("elmc", core_ir, module_name, function_prefix, eval_timeout_ms)

          {:error, reason} ->
            %{engine: "elmc", status: "core_ir_error", error: inspect(reason)}
        end

      {:error, reason} ->
        %{engine: "elmc", status: "compile_error", error: inspect(reason)}
    end
  end

  defp run("elm_executor", project_dir, out_dir, module_name, function_prefix, eval_timeout_ms) do
    case ElmExecutor.compile(project_dir, %{out_dir: out_dir, strip_dead_code: false, strict_core_ir: false}) do
      {:ok, %{core_ir: core_ir}} ->
        eval_core_ir("elm_executor", core_ir, module_name, function_prefix, eval_timeout_ms)

      {:error, reason} ->
        %{engine: "elm_executor", status: "compile_error", error: inspect(reason)}
    end
  end

  defp eval_core_ir(engine, core_ir, module_name, function_prefix, eval_timeout_ms) do
    functions = ElmExecutor.Runtime.CoreIREvaluator.index_functions(core_ir)

    targets =
      functions
      |> Enum.filter(fn
        {{mod, name, arity}, _defn} ->
          mod == module_name and arity == 0 and String.starts_with?(name, function_prefix)

        _ ->
          false
      end)
      |> Enum.sort_by(fn {{_mod, name, _arity}, _defn} -> function_sort_key(name, function_prefix) end)

    results =
      Enum.map(targets, fn {{_mod, name, _arity}, defn} ->
        ctx = %{functions: functions, module: module_name, source_module: module_name}

        task =
          Task.async(fn ->
            ElmExecutor.Runtime.CoreIREvaluator.evaluate(defn.body, %{}, ctx)
          end)

        case Task.yield(task, eval_timeout_ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, {:ok, value}} ->
            %{name: name, ok: true, value: json_safe(value)}

          {:ok, {:error, reason}} ->
            %{name: name, ok: false, error: inspect(reason)}

          nil ->
            %{name: name, ok: false, error: "timeout_after_#{eval_timeout_ms}ms"}

          {:exit, reason} ->
            %{name: name, ok: false, error: "task_exit: " <> inspect(reason)}
        end
      end)

    %{
      engine: engine,
      status: "ok",
      module: module_name,
      function_prefix: function_prefix,
      result_count: length(results),
      results: results
    }
  end

  defp function_sort_key(name, prefix) do
    rest = String.replace_prefix(name, prefix, "")

    case Integer.parse(rest) do
      {int, ""} -> {0, int}
      _ -> {1, name}
    end
  end

  defp json_safe(v) when is_integer(v) or is_float(v) or is_boolean(v) or is_binary(v), do: v
  defp json_safe(nil), do: nil

  defp json_safe(list) when is_list(list), do: Enum.map(list, &json_safe/1)

  defp json_safe(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&json_safe/1)
    |> then(&%{"tuple" => &1})
  end

  defp json_safe(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), json_safe(v)} end)
    |> Map.new()
  end

  defp json_safe(other), do: inspect(other)

  defp parse_args(argv) do
    parse_args(argv, %{})
  end

  defp parse_args([], acc), do: acc

  defp parse_args(["--" <> key, value | rest], acc) do
    if String.starts_with?(value, "--") do
      parse_args([value | rest], Map.put(acc, key, "true"))
    else
      parse_args(rest, Map.put(acc, key, value))
    end
  end

  defp parse_args(["--" <> key | rest], acc) do
    parse_args(rest, Map.put(acc, key, "true"))
  end

  defp parse_args([_other | rest], acc), do: parse_args(rest, acc)

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end
end

DocSnippetRuntimeEval.main(System.argv())
