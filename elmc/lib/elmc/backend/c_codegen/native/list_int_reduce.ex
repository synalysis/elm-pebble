defmodule Elmc.Backend.CCodegen.Native.ListIntReduce do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.SequenceLoopCodegen
  alias Elmc.Backend.CCodegen.Types

  @type spec :: %{
          list_arg: String.t(),
          base: Types.ir_expr(),
          head: String.t(),
          step: Types.ir_expr()
        }

  @spec recognize(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          {:ok, spec()} | :error
  def recognize(%{args: [list_arg], type: type, expr: expr, name: fn_name}, module_name, _decl_map)
      when is_binary(type) and is_binary(list_arg) and is_binary(fn_name) do
    with true <- Host.function_return_type(type) == "Int",
         [arg_type] <- Host.function_arg_types(type),
         true <- list_int_type?(arg_type),
         {:ok, base, head, _tail, step} <- case_add_fold(expr, list_arg, module_name, fn_name),
         true <- Host.native_int_expr?(base, %{__module__: module_name}),
         true <- Host.native_int_expr?(step, loop_env(module_name, head)) do
      {:ok, %{list_arg: list_arg, base: base, head: head, step: step}}
    else
      _ -> :error
    end
  end

  def recognize(_decl, _module_name, _decl_map), do: :error

  @spec compile(
          spec(),
          Types.compile_env(),
          :native_int | :native_bool,
          (Types.ir_expr(), Types.compile_env(), :native_int | :native_bool, Types.compile_counter() ->
             Types.compile_result())
        ) :: {:ok, String.t(), String.t()} | :error
  def compile(%{list_arg: list_arg, base: base, head: head, step: step}, env, return_kind, compile_step)
      when return_kind in [:native_int, :native_bool] do
    with list_ref when is_binary(list_ref) <- Map.get(env, list_arg),
         {base_code, base_ref, _} <- compile_step.(base, env, return_kind, 0) do
      loop_id = System.unique_integer([:positive])
      head_native = "list_reduce_head_#{loop_id}"
      acc = "list_reduce_acc_#{loop_id}"

      loop_env =
        env
        |> EnvBindings.put_native_int_binding(head, head_native)
        |> EnvBindings.put_boxed_int_binding(head, true)

      {step_code, step_ref, _} = compile_step.(step, loop_env, return_kind, 0)

      loop_body = """
      #{step_code}
          #{acc} += #{step_ref};
      """

      walk =
        SequenceLoopCodegen.emit_native_head_loop(
          list_ref,
          loop_id,
          head_native,
          loop_body,
          loop_env,
          list_arg
        )

      code = """
      #{base_code}
        elmc_int_t #{acc} = #{base_ref};
      #{walk}
      """

      {:ok, code, acc}
    else
      _ -> :error
    end
  end

  def compile(_spec, _env, _return_kind, _compile_step), do: :error

  @spec list_int_type?(String.t()) :: boolean()
  defp list_int_type?(type) do
    case Host.normalize_type_name(type) do
      "List Int" -> true
      _other -> false
    end
  end

  @spec loop_env(String.t(), String.t()) :: Types.compile_env()
  defp loop_env(module_name, head) do
    %{__module__: module_name}
    |> EnvBindings.put_native_int_binding(head, "list_reduce_head")
    |> EnvBindings.put_boxed_int_binding(head, true)
  end

  @spec case_add_fold(Types.ir_expr(), String.t(), String.t(), String.t()) ::
          {:ok, Types.ir_expr(), String.t(), String.t(), Types.ir_expr()} | :error
  defp case_add_fold(%{op: :case, subject: subject, branches: branches}, list_arg, module_name, fn_name) do
    with true <- case_subject?(subject, list_arg),
         {:ok, base} <- empty_branch(branches),
         {:ok, head, tail, step} <- cons_add_branch(branches, module_name, fn_name) do
      {:ok, base, head, tail, step}
    else
      _ -> :error
    end
  end

  defp case_add_fold(_expr, _list_arg, _module_name, _fn_name), do: :error

  @spec case_subject?(Types.ir_expr() | String.t(), String.t()) :: boolean()
  defp case_subject?(subject, list_arg) when is_binary(subject), do: subject == list_arg

  defp case_subject?(%{op: :var, name: name}, list_arg) when is_binary(name),
    do: name == list_arg

  defp case_subject?(_subject, _list_arg), do: false

  @spec empty_branch(Types.case_branches()) :: {:ok, Types.ir_expr()} | :error
  defp empty_branch(branches) do
    case Enum.find(branches, &empty_pattern?/1) do
      %{expr: expr} -> {:ok, expr}
      nil -> :error
    end
  end

  @spec empty_pattern?(Types.case_branch()) :: boolean()
  defp empty_pattern?(%{pattern: %{resolved_name: "[]"}}), do: true
  defp empty_pattern?(%{pattern: %{name: "[]", kind: :constructor}}), do: true
  defp empty_pattern?(_branch), do: false

  @spec cons_add_branch(Types.case_branches(), String.t(), String.t()) ::
          {:ok, String.t(), String.t(), Types.ir_expr()} | :error
  defp cons_add_branch(branches, module_name, fn_name) do
    case Enum.find(branches, &cons_pattern?/1) do
      %{pattern: pattern, expr: expr} ->
        with {:ok, head, tail} <- cons_bind_names(pattern),
             {:ok, step} <- add_step(expr, tail, module_name, fn_name) do
          {:ok, head, tail, step}
        else
          _ -> :error
        end

      nil ->
        :error
    end
  end

  @spec cons_pattern?(Types.case_branch()) :: boolean()
  defp cons_pattern?(%{pattern: %{resolved_name: "List.::"}}), do: true
  defp cons_pattern?(%{pattern: %{name: "::", kind: :constructor}}), do: true
  defp cons_pattern?(_branch), do: false

  @spec cons_bind_names(Types.pattern()) :: {:ok, String.t(), String.t()} | :error
  defp cons_bind_names(%{
         arg_pattern: %{kind: :tuple, elements: [head_pat, tail_pat]}
       }) do
    with %{kind: :var, name: head} when is_binary(head) <- head_pat,
         %{kind: :var, name: tail} when is_binary(tail) <- tail_pat do
      {:ok, head, tail}
    else
      _ -> :error
    end
  end

  defp cons_bind_names(_pattern), do: :error

  @spec add_step(Types.ir_expr(), String.t(), String.t(), String.t()) ::
          {:ok, Types.ir_expr()} | :error
  defp add_step(%{op: :call, name: "__add__", args: [left, right]}, tail, module_name, fn_name) do
    cond do
      self_on_list_tail?(left, tail, module_name, fn_name) ->
        {:ok, right}

      self_on_list_tail?(right, tail, module_name, fn_name) ->
        {:ok, left}

      true ->
        :error
    end
  end

  defp add_step(_expr, _tail, _module_name, _fn_name), do: :error

  @spec self_on_list_tail?(Types.ir_expr(), String.t(), String.t(), String.t()) :: boolean()
  defp self_on_list_tail?(%{op: :call, name: name, args: [arg]}, tail, _module_name, fn_name)
       when is_binary(name) and is_binary(tail) and is_binary(fn_name) do
    name == fn_name and tail_var?(arg, tail)
  end

  defp self_on_list_tail?(%{op: :qualified_call, target: target, args: [arg]}, tail, module_name, fn_name)
       when is_binary(target) and is_binary(tail) and is_binary(module_name) and is_binary(fn_name) do
    target in ["#{module_name}.#{fn_name}", fn_name] and tail_var?(arg, tail)
  end

  defp self_on_list_tail?(_expr, _tail, _module_name, _fn_name), do: false

  @spec tail_var?(Types.ir_expr(), String.t()) :: boolean()
  defp tail_var?(%{op: :var, name: name}, tail) when is_binary(name) and is_binary(tail),
    do: name == tail

  defp tail_var?(name, tail) when is_binary(name) and is_binary(tail), do: name == tail
  defp tail_var?(_expr, _tail), do: false
end
