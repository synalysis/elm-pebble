defmodule Elmx.Backend.ElixirCodegen.Emit.Qualified do
  @moduledoc """
  Lowers IR `qualified_call` nodes to runtime Elixir.

  Resolution order: `QualifiedRewrite` → Pebble rewrites → `Qualified.PebbleUi` →
  `Qualified.List` / `String` / `Collections` → `compile_qualified_call_fallback/4`
  (stdlib IR, `Qualified.Basics`, `Qualified.Bitwise`, then string fallback).

  Domain helpers live under `Emit.Qualified.*`; shared types in `Emit.Qualified.Context`.
  String codegen fragments: `Stdlib.QualifiedCodegen`.
  """

  alias Elmx.Backend.CrossModuleCall
  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Basics, as: QualifiedBasics
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Bitwise, as: QualifiedBitwise
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Collections, as: QualifiedCollections
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.CorpusPackages, as: QualifiedCorpusPackages
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Context
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.List, as: QualifiedList
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.PebbleUi, as: QualifiedPebbleUi
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.String, as: QualifiedString
  alias Elmx.Backend.OversaturatedQualified
  alias Elmx.Backend.QualifiedRewrite
  alias Elmx.Runtime.Pebble
  alias Elmx.Runtime.Pebble.SpecialValues
  alias Elmx.Runtime.Stdlib

  @type env :: Context.env()
  @type emit_counter :: Context.emit_counter()
  @type ir_arg_list :: Context.ir_arg_list()
  @type compile_expr_result :: Context.compile_expr_result()
  @type qualified_result :: Context.qualified_result()

  @pipeline_flatten_threshold 16

  def compile_qualified_call1(%{target: target}, env, counter) when is_binary(target) do
    case Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_constructor_reference(target, env, counter) do
      {:ok, code, env, c} ->
        {code, env, c}

      :error ->
        case SpecialValues.rewrite(target, []) do
          {:ok, rewritten} ->
            Elmx.Backend.ElixirCodegen.Emit.compile_expr(rewritten, env, counter)

          :error ->
            case Stdlib.special_call(target, "") do
              {:ok, code} ->
                {code, env, counter}

              :error ->
                raise Elmx.Backend.UnsupportedOpError,
                  op: :qualified_call1,
                  expr: %{target: target}
            end
        end
    end
  end

  def compile_qualified_call(%{target: _target, args: _args} = expr, env, counter) do
    expr = OversaturatedQualified.normalize(expr)

    case expr do
      %{op: op} when op != :qualified_call ->
        Emit.compile_expr(expr, env, counter)

      normalized ->
        case unwrap_qualified_pipeline(normalized) do
          {:ok, targets, base} when length(targets) >= @pipeline_flatten_threshold ->
            compile_qualified_pipeline_block(targets, base, env, counter)

          _ ->
            do_compile_qualified_call(normalized, env, counter)
        end
    end
  end

  defp do_compile_qualified_call(%{target: target, args: args}, env, counter) do
    case QualifiedRewrite.rewrite(target, args) do
      {:ok, rewritten} ->
        Elmx.Backend.ElixirCodegen.Emit.compile_expr(rewritten, env, counter)

      :error ->
        case Pebble.rewrite_qualified_call(target, args) do
          {:ok, rewritten} ->
            Elmx.Backend.ElixirCodegen.Emit.compile_expr(rewritten, env, counter)

          :error ->
            dispatch_qualified(target, args, env, counter)
        end
    end
  end

  defp unwrap_qualified_pipeline(expr), do: unwrap_qualified_pipeline(expr, [])

  defp unwrap_qualified_pipeline(%{op: :qualified_call, target: target, args: [inner]}, acc)
       when is_binary(target) do
    case inner do
      %{op: :qualified_call, args: [_single_arg]} ->
        unwrap_qualified_pipeline(inner, [target | acc])

      _ ->
        if acc == [] do
          :error
        else
          {:ok, Enum.reverse([target | acc]), inner}
        end
    end
  end

  defp unwrap_qualified_pipeline(_base, _acc), do: :error

  defp compile_qualified_pipeline_block(targets, base, env, counter) do
    {rest, homogeneous} = split_homogeneous_run(targets)

    if length(homogeneous) >= @pipeline_flatten_threshold do
      compile_qualified_homogeneous_run(hd(homogeneous), length(homogeneous), base, rest, env, counter)
    else
      compile_qualified_pipeline_iterative(targets, base, env, counter)
    end
  end

  defp split_homogeneous_run(targets) do
    case Enum.reverse(targets) do
      [first | rest] ->
        {same, other} = Enum.split_while(rest, &(&1 == first))
        homogeneous = Enum.reverse([first | same])
        remainder = Enum.reverse(other)
        {remainder, homogeneous}

      [] ->
        {[], []}
    end
  end

  defp compile_qualified_homogeneous_run(target, count, base, rest, env, counter) do
    {base_code, env, c0} = Emit.compile_expr(base, env, counter)
    acc_name = Helpers.let_emit_name("__pipe_acc")
    acc_atom = String.to_atom(acc_name)
    acc_var = Macro.to_string(Macro.var(acc_atom, nil))
    step_env = Map.put(env, acc_atom, true)

    step_expr = %{
      op: :qualified_call,
      target: target,
      args: [%{op: :var, name: acc_name}]
    }

    {step_code, _, c1} = do_compile_qualified_call(step_expr, step_env, c0)

    {rest_lines, _, c} =
      Enum.reduce(Enum.reverse(rest), {[], step_env, c1}, fn rest_target, {lines, env, c} ->
        rest_step = %{
          op: :qualified_call,
          target: rest_target,
          args: [%{op: :var, name: acc_name}]
        }

        {rest_code, _, c2} = do_compile_qualified_call(rest_step, env, c)
        {[ [acc_var, " = ", rest_code, "\n"] | lines], env, c2}
      end)

    code = [
      "(fn ->\n",
      acc_var,
      " = ",
      base_code,
      "\n",
      acc_var,
      " = Elmx.Runtime.Core.Apply.repeat1(",
      step_code,
      ", ",
      Integer.to_string(count),
      ", ",
      acc_var,
      ")\n",
      Enum.reverse(rest_lines),
      acc_var,
      "\nend).()"
    ]

    {code, env, c}
  end

  defp compile_qualified_pipeline_iterative(targets, base, env, counter) do
    {base_code, env, c0} = Emit.compile_expr(base, env, counter)
    acc_name = Helpers.let_emit_name("__pipe_acc")
    acc_atom = String.to_atom(acc_name)
    acc_var = Macro.to_string(Macro.var(acc_atom, nil))
    step_env = Map.put(env, acc_atom, true)

    {step_lines, _, c} =
      Enum.reduce(Enum.reverse(targets), {[], step_env, c0}, fn target, {lines, env, c} ->
        step_expr = %{
          op: :qualified_call,
          target: target,
          args: [%{op: :var, name: acc_name}]
        }

        {step_code, _, c1} = do_compile_qualified_call(step_expr, env, c)
        line = [acc_var, " = ", step_code, "\n"]
        {[line | lines], env, c1}
      end)

    step_lines = Enum.reverse(step_lines)

    code = [
      "(fn ->\n",
      acc_var,
      " = ",
      base_code,
      "\n",
      step_lines,
      acc_var,
      "\nend).()"
    ]

    {code, env, c}
  end

  defp dispatch_qualified(target, args, env, counter) do
    case try_domain_qualified(target, args, env, counter) do
      {:ok, code, env, c} ->
        {code, env, c}

      :error ->
        compile_qualified_call_fallback(target, args, env, counter)
    end
  end

  defp try_domain_qualified(target, args, env, counter) do
    QualifiedCorpusPackages.compile(target, args, env, counter)
    |> case do
      {:ok, _, _, _} = ok ->
        ok

      :error ->
        try_domain_qualified_stdlib(target, args, env, counter)
    end
  end

  defp try_domain_qualified_stdlib(target, args, env, counter) do
    QualifiedPebbleUi.compile(target, args, env, counter)
    |> case do
      {:ok, _, _, _} = ok ->
        ok

      :error ->
        QualifiedList.compile(target, args, env, counter)
        |> case do
          {:ok, _, _, _} = ok ->
            ok

          :error ->
            QualifiedString.compile(target, args, env, counter)
            |> case do
              {:ok, _, _, _} = ok -> ok
              :error -> QualifiedCollections.compile(target, args, env, counter)
            end
        end
    end
  end

  defdelegate compile_pebble_ui_qualified(target, args, env, counter),
    to: QualifiedPebbleUi,
    as: :compile

  defdelegate pebble_ui_call(fun, args, env, counter), to: QualifiedPebbleUi

  defdelegate compile_list_qualified(target, args, env, counter),
    to: QualifiedList,
    as: :compile

  defdelegate compile_string_qualified(target, args, env, counter),
    to: QualifiedString,
    as: :compile

  defdelegate compile_collections_qualified(target, args, env, counter),
    to: QualifiedCollections,
    as: :compile

  @spec compile_qualified_call_fallback(String.t(), ir_arg_list(), env(), emit_counter()) ::
          compile_expr_result()
  def compile_qualified_call_fallback(target, args, env, counter) do
    case compile_stdlib_qualified_ir(target, args, env, counter) do
      {:ok, code, env, c} ->
        {code, env, c}

      :error ->
        case QualifiedBasics.compile(target, args, env, counter) do
          {:ok, code, env, c} ->
            {code, env, c}

          :error ->
            case QualifiedBitwise.compile(target, args, env, counter) do
              {:ok, code, env, c} ->
                {code, env, c}

              :error ->
                compile_qualified_call_fallback_string(target, args, env, counter)
            end
        end
    end
  end

  @doc false
  def compile_stdlib_qualified_ir(target, args, env, counter)
      when is_binary(target) and is_list(args) do
    if Stdlib.handles_qualified?(target) do
      {arg_code, env, c} =
        Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_arg_list(args, env, counter)

      case Stdlib.qualified_call(target, IO.iodata_to_binary(arg_code)) do
        {:ok, code} -> {:ok, code, env, c}
        :error -> :error
      end
    else
      :error
    end
  end

  defdelegate compile_basics_qualified(target, args, env, counter), to: QualifiedBasics, as: :compile
  defdelegate compile_bitwise_qualified(target, args, env, counter), to: QualifiedBitwise, as: :compile

  @spec compile_qualified_call_fallback_string(String.t(), ir_arg_list(), env(), emit_counter()) ::
          compile_expr_result()
  def compile_qualified_call_fallback_string(target, args, env, counter) do
    {arg_code, env, c1} =
      Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_arg_list(args, env, counter)

    arg_str = IO.iodata_to_binary(arg_code)

    case Stdlib.qualified_call(target, arg_str) do
      {:ok, code} ->
        {code, env, c1}

      :error ->
        case CrossModuleCall.compile_call(target, args, env, counter, &Helpers.compile_arg_parts/3) do
          {:ok, code, env, c2} ->
            {code, env, c2}

          :error ->
            if String.contains?(target, ".") do
              raise Elmx.Backend.UnsupportedOpError,
                op: :qualified_call,
                expr: %{target: target, args: args}
            else
              fn_name = Helpers.qualified_fn_name(target)
              module = Map.get(env, :module, "Main")
              {[Helpers.module_fn(module, fn_name), "(", arg_str, ")"], env, c1}
            end
        end
    end
  end
end
