defmodule Elmc.Backend.CCodegen.Native.ListIntSearch do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @type help_spec :: %{
          target: String.t(),
          index: String.t(),
          list_arg: String.t(),
          head: String.t(),
          not_found: Types.ir_expr()
        }

  @type delegate_spec :: %{
          help_module: String.t(),
          help_name: String.t(),
          target: String.t(),
          list_arg: String.t()
        }

  @spec recognized?(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          boolean()
  def recognized?(decl, module_name, decl_map) do
    match?({:ok, _}, recognize(decl, module_name, decl_map)) or
      match?({:ok, _}, recognize_delegate(decl, module_name, decl_map))
  end

  @spec recognize(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          {:ok, help_spec()} | :error
  def recognize(
        %{args: [target, index, list_arg], type: type, expr: expr, name: fn_name},
        module_name,
        _decl_map
      )
      when is_binary(type) and is_binary(target) and is_binary(index) and is_binary(list_arg) and
             is_binary(fn_name) do
    with true <- Host.function_return_type(type) == "Int",
         arg_types when length(arg_types) == 3 <- Host.function_arg_types(type),
         true <- int_type?(Enum.at(arg_types, 0)),
         true <- int_type?(Enum.at(arg_types, 1)),
         true <- list_int_type?(Enum.at(arg_types, 2)),
         {:ok, not_found, head, tail, match_zero} <-
           case_search(expr, target, index, list_arg, module_name, fn_name),
         true <- match_zero == 0,
         true <- Host.native_int_expr?(not_found, %{__module__: module_name}) do
      {:ok,
       %{
         target: target,
         index: index,
         list_arg: list_arg,
         head: head,
         not_found: not_found,
         tail: tail
       }}
    else
      _ -> :error
    end
  end

  def recognize(_decl, _module_name, _decl_map), do: :error

  @spec recognize_delegate(Types.function_declaration(), String.t(), Types.function_decl_map()) ::
          {:ok, delegate_spec()} | :error
  def recognize_delegate(
        %{args: [target, list_arg], type: type, expr: expr},
        module_name,
        decl_map
      )
      when is_binary(type) and is_binary(target) and is_binary(list_arg) do
    with true <- Host.function_return_type(type) == "Int",
         [target_type, list_type] <- Host.function_arg_types(type),
         true <- int_type?(target_type),
         true <- list_int_type?(list_type),
         {:ok, help_module, help_name, help_target, zero, help_list} <-
           help_call(expr, module_name),
         true <- var_name?(help_target, target),
         true <- var_name?(help_list, list_arg),
         true <- zero_literal?(zero),
         {:ok, help_decl} <- Map.fetch(decl_map, {help_module, help_name}),
         {:ok, _help_spec} <- recognize(help_decl, help_module, decl_map) do
      {:ok, %{help_module: help_module, help_name: help_name, target: target, list_arg: list_arg}}
    else
      _ -> :error
    end
  end

  def recognize_delegate(_decl, _module_name, _decl_map), do: :error

  @spec arg_kinds(Types.function_declaration(), String.t(), Types.function_decl_map()) :: :error | {:ok, [atom()]}
  def arg_kinds(decl, module_name, decl_map) do
    cond do
      match?({:ok, _}, recognize(decl, module_name, decl_map)) ->
        {:ok, [:native_int, :native_int, :boxed]}

      match?({:ok, _}, recognize_delegate(decl, module_name, decl_map)) ->
        {:ok, [:native_int, :boxed]}

      true ->
        :error
    end
  end

  @spec compile(
          help_spec(),
          Types.compile_env(),
          :native_int | :native_bool,
          (Types.ir_expr(), Types.compile_env(), :native_int | :native_bool, Types.compile_counter() ->
             Types.compile_result())
        ) :: {:ok, String.t(), String.t()} | :error
  def compile(
        %{target: target, index: index, list_arg: list_arg, not_found: not_found},
        env,
        return_kind,
        compile_step
      )
      when return_kind in [:native_int, :native_bool] do
    with target_ref when is_binary(target_ref) <- EnvBindings.native_int_binding(env, target),
         index_ref when is_binary(index_ref) <- EnvBindings.native_int_binding(env, index),
         list_ref when is_binary(list_ref) <- Map.get(env, list_arg),
         {not_found_code, not_found_ref, _} <- compile_step.(not_found, env, return_kind, 0) do
      loop_id = System.unique_integer([:positive])
      cursor = "list_search_cursor_#{loop_id}"
      node = "list_search_node_#{loop_id}"
      head_native = "list_search_head_#{loop_id}"
      target_loop = "list_search_target_#{loop_id}"
      index_loop = "list_search_index_#{loop_id}"
      result = "list_search_result_#{loop_id}"

      code = """
      #{not_found_code}
        elmc_int_t #{target_loop} = #{target_ref};
        elmc_int_t #{index_loop} = #{index_ref};
        elmc_int_t #{result} = #{not_found_ref};
        ElmcValue *#{cursor} = #{list_ref};
        while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
          ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
          const elmc_int_t #{head_native} = elmc_as_int(#{node}->head);
          if ((#{head_native} == 0)) {
            if ((#{target_loop} == 0)) {
              #{result} = #{index_loop};
              break;
            }
            #{target_loop} -= 1;
          }
          #{index_loop} += 1;
          #{cursor} = #{node}->tail;
        }
      """

      {:ok, code, result}
    else
      _ -> :error
    end
  end

  def compile(_spec, _env, _return_kind, _compile_step), do: :error

  @spec compile_delegate(delegate_spec(), Types.compile_env()) :: {:ok, String.t(), String.t()} | :error
  def compile_delegate(%{help_module: help_module, help_name: help_name, target: target, list_arg: list_arg}, env) do
    with target_ref when is_binary(target_ref) <- EnvBindings.native_int_binding(env, target),
         list_ref when is_binary(list_ref) <- Map.get(env, list_arg) do
      c_name = Util.module_fn_name(help_module, help_name)

      code = """
        elmc_int_t list_search_delegate_1 = #{c_name}_native(#{target_ref}, 0, #{list_ref});
      """

      {:ok, code, "list_search_delegate_1"}
    else
      _ -> :error
    end
  end

  @spec int_type?(String.t()) :: boolean()
  defp int_type?(type), do: Host.normalize_type_name(type) == "Int"

  @spec list_int_type?(String.t()) :: boolean()
  defp list_int_type?(type), do: Host.normalize_type_name(type) == "List Int"

  @spec zero_literal?(Types.ir_expr()) :: boolean()
  defp zero_literal?(%{op: :int_literal, value: 0}), do: true
  defp zero_literal?(_expr), do: false

  @spec case_search(Types.ir_expr(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Types.ir_expr(), String.t(), String.t(), integer()} | :error
  defp case_search(
         %{op: :case, subject: subject, branches: branches},
         target,
         index,
         list_arg,
         module_name,
         fn_name
       ) do
    with true <- case_subject?(subject, list_arg),
         {:ok, not_found} <- empty_branch(branches),
         {:ok, head, tail, match_zero, cons_expr} <- cons_branch(branches),
         true <- match_zero == 0,
         true <-
           cons_search_body?(cons_expr, target, index, head, tail, module_name, fn_name) do
      {:ok, not_found, head, tail, match_zero}
    else
      _ -> :error
    end
  end

  defp case_search(_expr, _target, _index, _list_arg, _module_name, _fn_name), do: :error

  @spec cons_search_body?(
          Types.ir_expr(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: boolean()
  defp cons_search_body?(
         %{
           op: :if,
           cond: %{op: :compare, left: %{name: head, op: :var}, right: %{value: 0, op: :int_literal}, kind: :eq},
           then_expr: then_expr,
           else_expr: else_expr
         },
         target,
         index,
         head,
         tail,
         module_name,
         fn_name
       )
       when is_binary(target) and is_binary(index) and is_binary(head) and is_binary(tail) do
    match_branch?(then_expr, target, index, tail, module_name, fn_name, dec_target: true) and
      match_branch?(else_expr, target, index, tail, module_name, fn_name, dec_target: false)
  end

  defp cons_search_body?(_expr, _target, _index, _head, _tail, _module_name, _fn_name), do: false

  @spec match_branch?(Types.ir_expr(), String.t(), String.t(), String.t(), String.t(), String.t(), keyword()) ::
          boolean()
  defp match_branch?(
         %{
           op: :if,
           cond: %{
             op: :compare,
             left: %{name: target, op: :var},
             right: %{value: 0, op: :int_literal},
             kind: :eq
           },
           then_expr: %{name: index, op: :var},
           else_expr: else_expr
         },
         target,
         index,
         tail,
         module_name,
         fn_name,
         dec_target: true
       )
       when is_binary(target) and is_binary(index) and is_binary(tail) do
    self_recurse?(
      else_expr,
      target,
      index,
      tail,
      module_name,
      fn_name,
      target_update: {:sub_const, 1},
      index_update: {:add_const, 1}
    )
  end

  defp match_branch?(else_expr, target, index, tail, module_name, fn_name, dec_target: false)
       when is_binary(target) and is_binary(index) and is_binary(tail) do
    self_recurse?(
      else_expr,
      target,
      index,
      tail,
      module_name,
      fn_name,
      target_update: :same,
      index_update: {:add_const, 1}
    )
  end

  defp match_branch?(_expr, _target, _index, _tail, _module_name, _fn_name, _opts), do: false

  @spec self_recurse?(
          Types.ir_expr(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          keyword()
        ) :: boolean()
  defp self_recurse?(
         %{op: :qualified_call, target: callee, args: [target_arg, index_arg, tail_arg]},
         target,
         index,
         tail,
         module_name,
         fn_name,
         target_update: target_update,
         index_update: index_update
       )
       when is_binary(target) and is_binary(index) and is_binary(tail) and is_binary(module_name) and
              is_binary(fn_name) do
    callee in ["#{module_name}.#{fn_name}", fn_name] and
      tail_var?(tail_arg, tail) and
      target_arg_matches?(target_arg, target, target_update) and
      index_arg_matches?(index_arg, index, index_update)
  end

  defp self_recurse?(
         %{op: :call, name: name, args: [target_arg, index_arg, tail_arg]},
         target,
         index,
         tail,
         _module_name,
         fn_name,
         target_update: target_update,
         index_update: index_update
       )
       when is_binary(target) and is_binary(index) and is_binary(tail) and is_binary(fn_name) do
    name == fn_name and
      tail_var?(tail_arg, tail) and
      target_arg_matches?(target_arg, target, target_update) and
      index_arg_matches?(index_arg, index, index_update)
  end

  defp self_recurse?(_expr, _target, _index, _tail, _module_name, _fn_name, _updates), do: false

  @spec target_arg_matches?(Types.ir_expr(), String.t(), :same | {:sub_const, integer()}) :: boolean()
  defp target_arg_matches?(%{name: target, op: :var}, target, :same), do: true

  defp target_arg_matches?(%{op: :sub_const, var: target, value: amount}, target, {:sub_const, amount}),
    do: true

  defp target_arg_matches?(_expr, _target, _update), do: false

  @spec index_arg_matches?(Types.ir_expr(), String.t(), {:add_const, integer()}) :: boolean()
  defp index_arg_matches?(%{op: :add_const, var: index, value: amount}, index, {:add_const, amount}),
    do: true

  defp index_arg_matches?(_expr, _index, _update), do: false

  @spec help_call(Types.ir_expr(), String.t()) ::
          {:ok, String.t(), String.t(), String.t(), Types.ir_expr(), String.t()} | :error
  defp help_call(%{op: :qualified_call, target: target, args: [target_arg, zero, list_arg]}, module_name) do
    with {help_module, help_name} <- split_target(target, module_name) do
      {:ok, help_module, help_name, target_arg, zero, list_arg}
    else
      _ -> :error
    end
  end

  defp help_call(%{op: :call, name: name, args: [target_arg, zero, list_arg]}, module_name)
       when is_binary(name) do
    {:ok, module_name, name, target_arg, zero, list_arg}
  end

  defp help_call(_expr, _module_name), do: :error

  @spec split_target(String.t(), String.t()) :: {String.t(), String.t()} | :error
  defp split_target(target, default_module) when is_binary(target) do
    case String.split(target, ".", parts: 2) do
      [module, name] -> {module, name}
      [name] -> {default_module, name}
      _ -> :error
    end
  end

  @spec case_subject?(Types.ir_expr() | String.t(), String.t()) :: boolean()
  defp case_subject?(subject, list_arg) when is_binary(subject), do: subject == list_arg

  defp case_subject?(%{op: :var, name: name}, list_arg) when is_binary(name),
    do: name == list_arg

  defp case_subject?(_subject, _list_arg), do: false

  @spec empty_branch([map()]) :: {:ok, Types.ir_expr()} | :error
  defp empty_branch(branches) do
    case Enum.find(branches, &empty_pattern?/1) do
      %{expr: expr} -> {:ok, expr}
      nil -> :error
    end
  end

  @spec empty_pattern?(map()) :: boolean()
  defp empty_pattern?(%{pattern: %{resolved_name: "[]"}}), do: true
  defp empty_pattern?(%{pattern: %{name: "[]", kind: :constructor}}), do: true
  defp empty_pattern?(_branch), do: false

  @spec cons_branch([map()]) ::
          {:ok, String.t(), String.t(), integer(), Types.ir_expr()} | :error
  defp cons_branch(branches) do
    case Enum.find(branches, &cons_pattern?/1) do
      %{pattern: pattern, expr: expr} ->
        with {:ok, head, tail} <- cons_bind_names(pattern),
             0 <- head_compare_zero(expr, head) do
          {:ok, head, tail, 0, expr}
        else
          _ -> :error
        end

      nil ->
        :error
    end
  end

  @spec head_compare_zero(Types.ir_expr(), String.t()) :: integer() | :error
  defp head_compare_zero(
         %{op: :if, cond: %{op: :compare, left: %{name: head, op: :var}, right: %{value: zero, op: :int_literal}}},
         head
       )
       when is_integer(zero),
       do: zero

  defp head_compare_zero(_expr, _head), do: :error

  @spec cons_pattern?(map()) :: boolean()
  defp cons_pattern?(%{pattern: %{resolved_name: "List.::"}}), do: true
  defp cons_pattern?(%{pattern: %{name: "::", kind: :constructor}}), do: true
  defp cons_pattern?(_branch), do: false

  @spec cons_bind_names(map()) :: {:ok, String.t(), String.t()} | :error
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

  @spec tail_var?(Types.ir_expr(), String.t()) :: boolean()
  defp tail_var?(%{op: :var, name: name}, tail) when is_binary(name) and is_binary(tail),
    do: name == tail

  defp tail_var?(name, tail) when is_binary(name) and is_binary(tail), do: name == tail
  defp tail_var?(_expr, _tail), do: false

  @spec var_name?(Types.ir_expr() | String.t(), String.t()) :: boolean()
  defp var_name?(%{op: :var, name: name}, expected) when is_binary(name) and is_binary(expected),
    do: name == expected

  defp var_name?(name, expected) when is_binary(name) and is_binary(expected), do: name == expected
  defp var_name?(_expr, _expected), do: false
end
