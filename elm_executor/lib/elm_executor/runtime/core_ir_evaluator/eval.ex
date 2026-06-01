defmodule ElmExecutor.Runtime.CoreIREvaluator.Eval do
  @moduledoc """
  Core IR expression evaluation dispatch.

  Expression evaluation op dispatch lives here; only the bare `value` fallback remains on
  `CoreIREvaluator.do_evaluate/4`.
  """

  alias ElmExecutor.Runtime.CoreIREvaluator
  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes

  @type host :: %{
          evaluate: (EvalTypes.expr(), EvalTypes.env(), map(), EvalTypes.eval_stack() ->
                       EvalTypes.eval_result()),
          compare: (term(), term(), term() -> boolean()),
          normalize_params: (list() | map() | nil -> [String.t()]),
          collect_ok: ([EvalTypes.eval_result()] -> EvalTypes.eval_result()),
          resolve_zero_arity_value:
            (String.t(), map(), EvalTypes.eval_stack() -> {:ok, term()} | :error),
          tuple_first: (term() -> term()),
          tuple_second: (term() -> term()),
          char_from_code: (term() -> term()),
          evaluate_with_env_lookup:
            (EvalTypes.expr() | EvalTypes.runtime_value() | String.t(), EvalTypes.env(), map(),
             EvalTypes.eval_stack() -> EvalTypes.eval_result()),
          normalize_record_fields: (term() -> [{term(), term()}]),
          field_access: (term(), term() -> term()),
          numeric_operand_from_var:
            (term(), EvalTypes.env(), map(), EvalTypes.eval_stack() -> EvalTypes.eval_result()),
          short_ctor_name: (String.t() -> String.t()),
          record_alias_fields: (map(), String.t() -> term()),
          record_alias_field_types: (map(), String.t() -> map()),
          record_alias_value: (list(), map(), list(), map() -> term()),
          call_function:
            (String.t(), list(), EvalTypes.env(), map(), EvalTypes.eval_stack() ->
               EvalTypes.eval_result()),
          call_callable:
            (term(), list(), EvalTypes.env(), map(), EvalTypes.eval_stack() ->
               EvalTypes.eval_result()),
          evaluate_case_branches:
            (list(), term(), EvalTypes.env(), map(), EvalTypes.eval_stack() ->
               EvalTypes.eval_result())
        }

  @spec evaluate(EvalTypes.expr(), EvalTypes.env(), map()) :: EvalTypes.eval_result()
  def evaluate(expr, env \\ %{}, context \\ %{}) do
    CoreIREvaluator.evaluate(expr, env, context)
  end

  @spec try_dispatch(
          atom() | String.t(),
          map(),
          EvalTypes.env(),
          map(),
          EvalTypes.eval_stack(),
          host()
        ) :: EvalTypes.eval_result() | :unsupported
  def try_dispatch(op, expr, env, context, stack, host) when is_map(expr) and is_map(host) do
    case try_literal_op(op, expr) do
      {:ok, value} ->
        {:ok, value}

      :unsupported ->
        case try_control_op(op, expr, env, context, stack, host) do
          :unsupported ->
            case try_data_op(op, expr, env, context, stack, host) do
              :unsupported ->
                case try_record_op(op, expr, env, context, stack, host) do
                  :unsupported ->
                    case try_arithmetic_op(op, expr, env, context, stack, host) do
                      :unsupported ->
                        case try_constructor_op(op, expr, env, context, stack, host) do
                          :unsupported -> try_call_op(op, expr, env, context, stack, host)
                          other -> other
                        end

                      other ->
                        other
                    end

                  other ->
                    other
                end

              other ->
                other
            end

          other ->
            other
        end
    end
  end

  @spec try_literal_op(atom() | String.t(), map()) :: {:ok, term()} | :unsupported
  def try_literal_op(op, expr) when is_map(expr) do
    case op do
      :int_literal ->
        {:ok, map_value(expr, "value")}

      :float_literal ->
        {:ok, map_value(expr, "value")}

      :bool_literal ->
        {:ok, map_value(expr, "value")}

      :char_literal ->
        {:ok, map_value(expr, "value")}

      :string_literal ->
        {:ok, map_value(expr, "value")}

      _ ->
        :unsupported
    end
  end

  @spec try_control_op(
          atom() | String.t(),
          map(),
          EvalTypes.env(),
          map(),
          EvalTypes.eval_stack(),
          host()
        ) :: EvalTypes.eval_result() | :unsupported
  def try_control_op(op, expr, env, context, stack, host)
      when is_map(expr) and is_map(env) and is_map(context) and is_list(stack) do
    %{evaluate: evaluate, compare: compare} = host
    case op do
      :expr ->
        inner =
          expr["expr"] || expr[:expr] || expr["value_expr"] || expr[:value_expr] ||
            expr["in_expr"] || expr[:in_expr]

        evaluate.(inner, env, context, stack)

      :let_in ->
        name = expr["name"] || expr[:name]
        value_expr = expr["value_expr"] || expr[:value_expr]
        in_expr = expr["in_expr"] || expr[:in_expr]

        with {:ok, value} <- evaluate.(value_expr, env, context, stack) do
          next_env = if is_binary(name), do: Map.put(env, name, value), else: env
          evaluate.(in_expr, next_env, context, stack)
        end

      :if ->
        with {:ok, condition} <- evaluate.(expr["cond"] || expr[:cond], env, context, stack) do
          if condition == true do
            evaluate.(expr["then_expr"] || expr[:then_expr], env, context, stack)
          else
            evaluate.(expr["else_expr"] || expr[:else_expr], env, context, stack)
          end
        end

      :compare ->
        with {:ok, left} <- evaluate.(expr["left"] || expr[:left], env, context, stack),
             {:ok, right} <- evaluate.(expr["right"] || expr[:right], env, context, stack) do
          {:ok, compare.(expr["kind"] || expr[:kind], left, right)}
        end

      :lambda ->
        params =
          host_normalize_params(host, expr["params"] || expr[:params] || expr["args"] || expr[:args])

        body = expr["body"] || expr[:body]
        {:ok, {:closure, params, body, env}}

      _ ->
        :unsupported
    end
  end

  @spec try_data_op(
          atom() | String.t(),
          map(),
          EvalTypes.env(),
          map(),
          EvalTypes.eval_stack(),
          host()
        ) :: EvalTypes.eval_result() | :unsupported
  def try_data_op(op, expr, env, context, stack, host)
      when is_map(expr) and is_map(env) and is_map(context) and is_list(stack) do
    %{evaluate: evaluate, collect_ok: collect_ok} = host

    case op do
      :var ->
        name = expr["name"] || expr[:name]

        cond do
          is_binary(name) ->
            case resolve_dotted_var_value(name, env, host) do
              {:ok, value} ->
                {:ok, value}

              :error ->
                value =
                  case String.downcase(name) do
                    "pi" -> :math.pi()
                    "e" -> :math.exp(1.0)
                    "lt" -> %{"ctor" => "LT", "args" => []}
                    "eq" -> %{"ctor" => "EQ", "args" => []}
                    "gt" -> %{"ctor" => "GT", "args" => []}
                    "empty" -> []
                    _ -> nil
                  end

                cond do
                  value != nil ->
                    {:ok, value}

                  true ->
                    case host_resolve_zero_arity(host, name, context, stack) do
                      {:ok, resolved} -> {:ok, resolved}
                      _ -> {:ok, {:function_ref, name}}
                    end
                end
            end

          true ->
            {:ok, nil}
        end

      :var_resolved ->
        evaluate.(expr["value_expr"] || expr[:value_expr], env, context, stack)

      :list_literal ->
        list = expr["items"] || expr[:items] || expr["elements"] || expr[:elements] || []

        list
        |> Enum.map(&evaluate.(&1, env, context, stack))
        |> collect_ok.()

      :tuple2 ->
        with {:ok, left} <- evaluate.(expr["left"] || expr[:left], env, context, stack),
             {:ok, right} <- evaluate.(expr["right"] || expr[:right], env, context, stack) do
          {:ok, {left, right}}
        end

      :tuple ->
        elements = expr["elements"] || expr[:elements] || []

        with true <- is_list(elements),
             {:ok, values} <-
               elements |> Enum.map(&evaluate.(&1, env, context, stack)) |> collect_ok.() do
          {:ok, List.to_tuple(values)}
        else
          _ -> {:error, {:unsupported_tuple, expr}}
        end

      :tuple_first_expr ->
        with {:ok, value} <- evaluate.(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, host_tuple_first(host, value)}
        end

      :tuple_second_expr ->
        with {:ok, value} <- evaluate.(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, host_tuple_second(host, value)}
        end

      :tuple_first ->
        with {:ok, value} <- evaluate.(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, host_tuple_first(host, value)}
        end

      :tuple_second ->
        with {:ok, value} <- evaluate.(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, host_tuple_second(host, value)}
        end

      :string_length_expr ->
        with {:ok, value} <- evaluate.(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, if(is_binary(value), do: String.length(value), else: 0)}
        end

      :char_from_code_expr ->
        with {:ok, value} <- evaluate.(expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, host_char_from_code(host, value)}
        end

      _ ->
        :unsupported
    end
  end

  @spec try_record_op(
          atom() | String.t(),
          map(),
          EvalTypes.env(),
          map(),
          EvalTypes.eval_stack(),
          host()
        ) :: EvalTypes.eval_result() | :unsupported
  def try_record_op(op, expr, env, context, stack, host)
      when is_map(expr) and is_map(env) and is_map(context) and is_list(stack) do
    %{evaluate: evaluate} = host

    case op do
      :field_access ->
        field = expr["field"] || expr[:field]

        with {:ok, base} <-
               host_evaluate_with_env_lookup(host, expr["arg"] || expr[:arg], env, context, stack) do
          {:ok, host_field_access(host, base, field)}
        end

      :record_literal ->
        fields = expr["fields"] || expr[:fields] || %{}

        map =
          host_normalize_record_fields(host, fields)
          |> Enum.reduce(%{}, fn {k, v}, acc ->
            case evaluate.(v, env, context, stack) do
              {:ok, value} -> Map.put(acc, to_string(k), value)
              _ -> Map.put(acc, to_string(k), nil)
            end
          end)

        {:ok, map}

      :record_update ->
        base_expr = expr["base"] || expr[:base]
        fields = expr["fields"] || expr[:fields] || []

        with {:ok, base} <- host_evaluate_with_env_lookup(host, base_expr, env, context, stack) do
          base = if is_map(base), do: base, else: %{}

          updated =
            host_normalize_record_fields(host, fields)
            |> Enum.reduce(base, fn {k, v}, acc ->
              case evaluate.(v, env, context, stack) do
                {:ok, value} -> Map.put(acc, to_string(k), value)
                _ -> acc
              end
            end)

          {:ok, updated}
        end

      _ ->
        :unsupported
    end
  end

  @spec try_arithmetic_op(
          atom() | String.t(),
          map(),
          EvalTypes.env(),
          map(),
          EvalTypes.eval_stack(),
          host()
        ) :: EvalTypes.eval_result() | :unsupported
  def try_arithmetic_op(op, expr, env, context, stack, host)
      when is_map(expr) and is_map(env) and is_map(context) and is_list(stack) do
    case op do
      :add_const ->
        name = expr["var"] || expr[:var]
        value = expr["value"] || expr[:value]

        with {:ok, left} <- host_numeric_operand(host, name, env, context, stack),
             right when is_number(right) <- value do
          {:ok, left + right}
        else
          _ -> {:error, {:invalid_add_const, name}}
        end

      :sub_const ->
        name = expr["var"] || expr[:var]
        value = expr["value"] || expr[:value]

        with {:ok, left} <- host_numeric_operand(host, name, env, context, stack),
             right when is_number(right) <- value do
          {:ok, left - right}
        else
          _ -> {:error, {:invalid_sub_const, name}}
        end

      :add_vars ->
        left_name = expr["left"] || expr[:left]
        right_name = expr["right"] || expr[:right]

        with {:ok, left} <- host_numeric_operand(host, left_name, env, context, stack),
             {:ok, right} <- host_numeric_operand(host, right_name, env, context, stack) do
          {:ok, left + right}
        else
          _ -> {:error, {:invalid_add_vars, left_name, right_name}}
        end

      _ ->
        :unsupported
    end
  end

  @spec try_constructor_op(
          atom() | String.t(),
          map(),
          EvalTypes.env(),
          map(),
          EvalTypes.eval_stack(),
          host()
        ) :: EvalTypes.eval_result() | :unsupported
  def try_constructor_op(op, expr, env, context, stack, host)
      when is_map(expr) and is_map(env) and is_map(context) and is_list(stack) do
    %{evaluate: evaluate, collect_ok: collect_ok} = host

    case op do
      :constructor_call ->
        target = to_string(expr["target"] || expr[:target] || "")
        args = expr["args"] || expr[:args] || []
        short = host_short_ctor_name(host, target)

        with {:ok, values} <-
               args |> Enum.map(&evaluate.(&1, env, context, stack)) |> collect_ok.() do
          alias_fields = host_record_alias_fields(host, context, target)

          cond do
            values == [] and alias_fields != nil ->
              {:ok,
               {:record_alias_constructor, short, alias_fields,
                host_record_alias_field_types(host, context, target)}}

            is_list(alias_fields) ->
              {:ok,
               host_record_alias_value(
                 host,
                 alias_fields,
                 host_record_alias_field_types(host, context, target),
                 values,
                 context
               )}

            true ->
              case {short, values} do
                {"True", []} ->
                  {:ok, true}

                {"False", []} ->
                  {:ok, false}

                _ ->
                  value = %{"ctor" => short, "args" => values}

                  {:ok,
                   case CoreIREvaluator.constructor_tag_for_ctor(short, context) do
                     tag when is_integer(tag) -> Map.put(value, "tag", tag)
                     _ -> value
                   end}
              end
          end
        end

      _ ->
        :unsupported
    end
  end

  defp host_normalize_params(%{normalize_params: normalize_params}, params)
       when is_function(normalize_params, 1),
       do: normalize_params.(params)

  defp host_normalize_params(_, _), do: []

  defp host_resolve_zero_arity(%{resolve_zero_arity_value: fun}, name, context, stack)
       when is_function(fun, 3),
       do: fun.(name, context, stack)

  defp host_resolve_zero_arity(_, _name, _context, _stack), do: :error

  defp host_tuple_first(%{tuple_first: fun}, value) when is_function(fun, 1), do: fun.(value)
  defp host_tuple_first(_, _), do: nil

  defp host_tuple_second(%{tuple_second: fun}, value) when is_function(fun, 1), do: fun.(value)
  defp host_tuple_second(_, _), do: nil

  defp host_char_from_code(%{char_from_code: fun}, value) when is_function(fun, 1),
    do: fun.(value)

  defp host_char_from_code(_, _), do: nil

  defp host_evaluate_with_env_lookup(host, expr, env, context, stack) do
    case host do
      %{evaluate_with_env_lookup: fun} when is_function(fun, 4) ->
        fun.(expr, env, context, stack)

      %{evaluate: evaluate} when is_function(evaluate, 4) ->
        evaluate.(expr, env, context, stack)
    end
  end

  defp host_normalize_record_fields(%{normalize_record_fields: fun}, fields)
       when is_function(fun, 1),
       do: fun.(fields)

  defp host_normalize_record_fields(_, _), do: []

  defp host_field_access(%{field_access: fun}, base, field) when is_function(fun, 2),
    do: fun.(base, field)

  defp host_field_access(_, _base, _field), do: nil

  defp host_numeric_operand(host, name, env, context, stack) do
    case host do
      %{numeric_operand_from_var: fun} when is_function(fun, 4) ->
        fun.(name, env, context, stack)

      _ ->
        {:error, :invalid_operand}
    end
  end

  defp host_short_ctor_name(%{short_ctor_name: fun}, target) when is_function(fun, 1),
    do: fun.(target)

  defp host_short_ctor_name(_, target), do: target

  defp host_record_alias_fields(%{record_alias_fields: fun}, context, target)
       when is_function(fun, 2),
       do: fun.(context, target)

  defp host_record_alias_fields(_, _context, _target), do: nil

  defp host_record_alias_field_types(%{record_alias_field_types: fun}, context, target)
       when is_function(fun, 2),
       do: fun.(context, target)

  defp host_record_alias_field_types(_, _context, _target), do: %{}

  defp host_record_alias_value(host, fields, field_types, values, context) do
    case host do
      %{record_alias_value: fun} when is_function(fun, 4) ->
        fun.(fields, field_types, values, context)

      _ ->
        %{}
    end
  end

  @spec try_call_op(
          atom() | String.t(),
          map(),
          EvalTypes.env(),
          map(),
          EvalTypes.eval_stack(),
          host()
        ) :: EvalTypes.eval_result() | :unsupported
  def try_call_op(op, expr, env, context, stack, host)
      when is_map(expr) and is_map(env) and is_map(context) and is_list(stack) do
    %{evaluate: evaluate, collect_ok: collect_ok} = host

    case op do
      :field_call ->
        field = expr["field"] || expr[:field]
        args = expr["args"] || expr[:args] || []

        with {:ok, base} <-
               host_evaluate_with_env_lookup(host, expr["arg"] || expr[:arg], env, context, stack),
             callable when not is_nil(callable) <- host_field_access(host, base, field),
             {:ok, values} <-
               args |> Enum.map(&evaluate.(&1, env, context, stack)) |> collect_ok.(),
             {:ok, value} <- host_call_callable(host, callable, values, env, context, stack) do
          {:ok, value}
        else
          nil -> {:error, {:unknown_field_call, field}}
          {:error, _} = err -> err
          _ -> {:error, {:invalid_field_call, field}}
        end

      :qualified_call ->
        target = to_string(expr["target"] || expr[:target] || "")
        args = expr["args"] || expr[:args] || []
        host_call_function(host, target, args, env, context, stack)

      :qualified_call1 ->
        target = to_string(expr["target"] || expr[:target] || "")
        args = expr["args"] || expr[:args] || []
        host_call_function(host, target, args, env, context, stack)

      :call ->
        name = to_string(expr["name"] || expr[:name] || "")
        args = expr["args"] || expr[:args] || []
        host_call_function(host, name, args, env, context, stack)

      :case ->
        with {:ok, subject} <-
               host_evaluate_with_env_lookup(
                 host,
                 expr["subject"] || expr[:subject],
                 env,
                 context,
                 stack
               ) do
          branches = expr["branches"] || expr[:branches] || []
          host_evaluate_case_branches(host, branches, subject, env, context, stack)
        end

      _ ->
        :unsupported
    end
  end

  defp host_call_function(host, name, args, env, context, stack) do
    case host do
      %{call_function: fun} when is_function(fun, 5) -> fun.(name, args, env, context, stack)
      _ -> {:error, {:unsupported_call, name}}
    end
  end

  defp host_call_callable(host, callable, values, env, context, stack) do
    case host do
      %{call_callable: fun} when is_function(fun, 5) -> fun.(callable, values, env, context, stack)
      _ -> {:error, :invalid_callable}
    end
  end

  defp host_evaluate_case_branches(host, branches, subject, env, context, stack) do
    case host do
      %{evaluate_case_branches: fun} when is_function(fun, 5) ->
        fun.(branches, subject, env, context, stack)

      _ ->
        {:error, :invalid_case_branches}
    end
  end

  @spec resolve_dotted_var_value(String.t(), EvalTypes.env(), host()) ::
          {:ok, EvalTypes.runtime_value()} | :error
  defp resolve_dotted_var_value(name, env, host) when is_binary(name) and is_map(env) do
    if Map.has_key?(env, name) do
      {:ok, Map.get(env, name)}
    else
      case String.split(name, ".") do
        [_] ->
          :error

        [root | fields] ->
          with {:ok, base} <- resolve_dotted_var_value(root, env, host) do
            fields
            |> Enum.reduce_while({:ok, base}, fn field, {:ok, acc} ->
              value = host_field_access(host, acc, field)

              if is_nil(value) do
                {:halt, :error}
              else
                {:cont, {:ok, value}}
              end
            end)
            |> case do
              {:ok, _} = ok -> ok
              :error -> :error
            end
          end
      end
    end
  end

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    map = if Map.has_key?(map, :__struct__), do: Map.from_struct(map), else: map

    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(map, fn
          {atom_key, value} when is_atom(atom_key) ->
            if Atom.to_string(atom_key) == key, do: {:ok, value}, else: nil

          _ ->
            nil
        end)
        |> case do
          {:ok, value} -> value
          nil -> nil
        end
    end
  end
end
