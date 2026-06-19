defmodule Elmc.Backend.CCodegen.Patterns do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.PebbleMsgTag
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec pattern_condition(String.t(), Types.pattern()) :: String.t()
  def pattern_condition(_subject_ref, %{kind: :wildcard}), do: "1"
  def pattern_condition(_subject_ref, %{kind: :var}), do: "1"

  def pattern_condition(subject_ref, pattern)
      when is_map(pattern) and not is_binary(subject_ref) do
    pattern_condition(pattern_subject_ref(subject_ref), pattern)
  end

  def pattern_condition(subject_ref, %{kind: :int, value: value}) when is_integer(value) do
    "#{subject_ref} && (#{subject_ref}->tag == ELMC_TAG_INT || #{subject_ref}->tag == ELMC_TAG_CHAR) && elmc_as_int(#{subject_ref}) == #{value}"
  end

  def pattern_condition(subject_ref, %{kind: :tuple, elements: elements})
      when is_list(elements) and length(elements) > 2 do
    pattern_condition(subject_ref, nest_tuple_pattern(elements))
  end

  def pattern_condition(subject_ref, %{kind: :tuple, elements: [left, right]}) do
    left_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->first"
    right_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_TUPLE2 && (#{pattern_condition(left_ref, left)}) && (#{pattern_condition(right_ref, right)})"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "()", arg_pattern: nil}) do
    "#{subject_ref} && elmc_value_is_unit(#{subject_ref})"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "()", arg_pattern: pattern})
      when not is_nil(pattern) do
    pattern_condition(subject_ref, pattern)
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "Ok", arg_pattern: arg_pattern}) do
    value_ref = "((ElmcResult *)#{subject_ref}->payload)->value"
    arg_cond = if arg_pattern, do: " && (#{pattern_condition(value_ref, arg_pattern)})", else: ""

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_RESULT && ((ElmcResult *)#{subject_ref}->payload)->is_ok == 1#{arg_cond}"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "Err", arg_pattern: arg_pattern}) do
    value_ref = "((ElmcResult *)#{subject_ref}->payload)->value"
    arg_cond = if arg_pattern, do: " && (#{pattern_condition(value_ref, arg_pattern)})", else: ""

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_RESULT && ((ElmcResult *)#{subject_ref}->payload)->is_ok == 0#{arg_cond}"
  end

  def pattern_condition(subject_ref, %{
        kind: :constructor,
        name: "Just",
        arg_pattern: arg_pattern
      }) do
    maybe_value_ref = "((ElmcMaybe *)#{subject_ref}->payload)->value"
    tuple_value_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"

    maybe_arg_cond =
      if arg_pattern, do: " && (#{pattern_condition(maybe_value_ref, arg_pattern)})", else: ""

    tuple_arg_cond =
      if arg_pattern, do: " && (#{pattern_condition(tuple_value_ref, arg_pattern)})", else: ""

    maybe_cond =
      "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)#{subject_ref}->payload)->is_just == 1#{maybe_arg_cond}"

    tuple_cond =
      "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_TUPLE2 && #{subject_ref}->payload != NULL && elmc_as_int(((ElmcTuple2 *)#{subject_ref}->payload)->first) == 1#{tuple_arg_cond}"

    "((#{maybe_cond}) || (#{tuple_cond}))"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "Nothing"}) do
    maybe_cond =
      "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)#{subject_ref}->payload)->is_just == 0"

    int_cond =
      "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_INT && elmc_as_int(#{subject_ref}) == 0"

    "((#{maybe_cond}) || (#{int_cond}))"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "[]"}) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_LIST && #{subject_ref}->payload == NULL"
  end

  def pattern_condition(subject_ref, %{
        kind: :constructor,
        name: "::",
        arg_pattern: %{kind: :tuple, elements: [head_pattern, tail_pattern]}
      }) do
    head_ref = "((ElmcCons *)#{subject_ref}->payload)->head"
    tail_ref = "((ElmcCons *)#{subject_ref}->payload)->tail"

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_LIST && #{subject_ref}->payload != NULL && (#{pattern_condition(head_ref, head_pattern)}) && (#{pattern_condition(tail_ref, tail_pattern)})"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "::"}) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_LIST && #{subject_ref}->payload != NULL"
  end

  def pattern_condition(_subject_ref, %{kind: :record}) do
    "1"
  end

  def pattern_condition(subject_ref, %{kind: :string, value: value}) when is_binary(value) do
    escaped = Util.escape_c_string(value)

    "#{subject_ref} && elmc_string_equals_cstr(#{subject_ref}, \"#{escaped}\")"
  end

  def pattern_condition(
        subject_ref,
        %{kind: :constructor, tag: tag, arg_pattern: arg_pattern} = pattern
      )
      when is_integer(tag) and is_map(arg_pattern) do
    tag_ref = PebbleMsgTag.tag_expr(pattern)
    value_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"
    arg_cond = constructor_arg_condition(value_ref, arg_pattern)

    tagged_match =
      "((#{subject_ref})->tag == ELMC_TAG_TUPLE2 && (#{subject_ref})->payload != NULL && elmc_as_int(((ElmcTuple2 *)(#{subject_ref})->payload)->first) == #{tag_ref}#{arg_cond})"

    "(#{subject_ref}) && #{tagged_match}"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, tag: tag} = pattern)
      when is_integer(tag) do
    tag_ref = PebbleMsgTag.tag_expr(pattern)

    int_match =
      "((#{subject_ref})->tag == ELMC_TAG_INT && elmc_as_int(#{subject_ref}) == #{tag_ref})"

    tuple_match =
      "((#{subject_ref})->tag == ELMC_TAG_TUPLE2 && (#{subject_ref})->payload != NULL && elmc_as_int(((ElmcTuple2 *)(#{subject_ref})->payload)->first) == #{tag_ref})"

    "(#{subject_ref}) && (#{int_match} || #{tuple_match})"
  end

  def pattern_condition(subject_ref, %{kind: :constructor} = pattern) do
    case order_constructor_name(pattern) do
      name when name in ["LT", "EQ", "GT"] ->
        order_constructor_condition(subject_ref, order_scalar(name))

      _ ->
        case bool_constructor_name(pattern) do
          "False" -> bool_constructor_condition(subject_ref, false)
          "True" -> bool_constructor_condition(subject_ref, true)
          _ -> "0"
        end
    end
  end

  def pattern_condition(_subject_ref, _pattern), do: "0"

  @spec bind_pattern(Types.compile_env(), Types.pattern(), Types.subject_ref()) ::
          Types.compile_env()
  def bind_pattern(env, %{kind: :wildcard}, _subject_ref), do: env

  def bind_pattern(env, %{kind: :var, name: bind}, subject_ref)
      when bind not in ["_", ""] do
    ref =
      if Map.get(env, :maybe_unwrap_just) do
        just_payload_ref(subject_ref)
      else
        pattern_subject_ref(subject_ref)
      end

    Map.put(env, bind, ref)
  end

  def bind_pattern(env, %{kind: :var, name: bind}, subject_ref) do
    Map.put(env, bind, pattern_subject_ref(subject_ref))
  end

  def bind_pattern(env, %{kind: :tuple, elements: elements}, subject_ref)
      when is_list(elements) and length(elements) > 2 do
    bind_pattern(env, nest_tuple_pattern(elements), subject_ref)
  end

  def bind_pattern(env, %{kind: :tuple, elements: [left, right]}, subject_ref) do
    subject_ref = pattern_subject_ref(subject_ref)

    env
    |> bind_pattern(left, "((ElmcTuple2 *)#{subject_ref}->payload)->first")
    |> bind_pattern(right, "((ElmcTuple2 *)#{subject_ref}->payload)->second")
  end

  def bind_pattern(
        env,
        %{kind: :constructor, name: "Ok", bind: bind, arg_pattern: arg},
        subject_ref
      ) do
    subject_ref = pattern_subject_ref(subject_ref)
    value_ref = "((ElmcResult *)#{subject_ref}->payload)->value"
    env = if is_binary(bind), do: Map.put(env, bind, value_ref), else: env
    if arg, do: bind_pattern(env, arg, value_ref), else: env
  end

  def bind_pattern(
        env,
        %{kind: :constructor, name: "Err", bind: bind, arg_pattern: arg},
        subject_ref
      ) do
    subject_ref = pattern_subject_ref(subject_ref)
    value_ref = "((ElmcResult *)#{subject_ref}->payload)->value"
    env = if is_binary(bind), do: Map.put(env, bind, value_ref), else: env
    if arg, do: bind_pattern(env, arg, value_ref), else: env
  end

  def bind_pattern(
        env,
        %{kind: :constructor, name: "Just", bind: bind, arg_pattern: arg},
        subject_ref
      ) do
    subject_ref = pattern_subject_ref(subject_ref)

    value_ref = just_payload_ref(subject_ref)

    env =
      env
      |> then(fn branch_env ->
        if is_binary(bind), do: Map.put(branch_env, bind, value_ref), else: branch_env
      end)
      |> put_just_bind_var_type(subject_ref, bind)

    if arg, do: bind_pattern(env, arg, value_ref), else: env
  end

  def bind_pattern(
        env,
        %{
          kind: :constructor,
          name: "::",
          bind: bind,
          arg_pattern: %{kind: :tuple, elements: [head, tail]}
        },
        subject_ref
      ) do
    subject_ref = pattern_subject_ref(subject_ref)
    list_int? = list_int_subject?(env, subject_ref)
    env = if is_binary(bind), do: Map.put(env, bind, subject_ref), else: env

    tail_ref = "((ElmcCons *)#{subject_ref}->payload)->tail"

    env
    |> bind_pattern(head, "((ElmcCons *)#{subject_ref}->payload)->head")
    |> bind_pattern(tail, tail_ref)
    |> EnvBindings.put_list_suffix_ref(tail_ref)
    |> maybe_mark_list_int_cons(head, tail, list_int?)
  end

  def bind_pattern(env, %{kind: :record, fields: fields, bind: bind}, subject_ref)
      when is_list(fields) do
    subject_ref = pattern_subject_ref(subject_ref)
    env = if is_binary(bind), do: Map.put(env, bind, subject_ref), else: env

    parent_expr =
      cond do
        is_binary(bind) -> %{op: :var, name: bind}
        true -> %{op: :var, name: subject_ref}
      end

    Enum.reduce(fields, env, fn field, acc ->
      case field do
        "value" ->
          Map.put(acc, field, "((ElmcTuple2 *)#{subject_ref}->payload)->first")

        "temperature" ->
          Map.put(acc, field, "((ElmcTuple2 *)#{subject_ref}->payload)->second")

        name when is_binary(name) and not is_nil(parent_expr) ->
          shape = Expr.record_shape(parent_expr, acc)
          type = Expr.record_container_type_for_expr(parent_expr, acc)
          getter = Expr.record_get_expr(subject_ref, name, shape, acc, type)

          field_type = RecordFields.field_type(acc, parent_expr, name)
          field_shape = if is_binary(field_type), do: Expr.record_shape_for_type(field_type, acc), else: nil

          acc
          |> Map.put(name, getter)
          |> put_pattern_field_record_shape(name, field_shape)

        name when is_binary(name) ->
          Map.put(acc, name, subject_ref)

        _ ->
          acc
      end
    end)
  end

  def bind_pattern(
        env,
        %{kind: :constructor, tag: tag, bind: bind, arg_pattern: arg},
        subject_ref
      )
      when is_integer(tag) do
    subject_ref = pattern_subject_ref(subject_ref)
    value_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"
    env = if is_binary(bind), do: Map.put(env, bind, value_ref), else: env
    if arg, do: bind_pattern(env, arg, value_ref), else: env
  end

  def bind_pattern(env, _pattern, _subject_ref), do: env

  @doc false
  @spec maybe_unwrap_just_case?(list()) :: boolean()
  def maybe_unwrap_just_case?(branches) when is_list(branches) do
    Enum.any?(branches, &nothing_branch?/1) and
      Enum.any?(branches, &var_branch?/1) and
      Enum.all?(branches, fn branch -> nothing_branch?(branch) or var_branch?(branch) end)
  end

  def maybe_unwrap_just_case?(_branches), do: false

  @doc """
  For `Nothing` + bare-var Maybe cases, bind the var to a single borrowed temp
  per branch so field reads do not leak one payload per `elmc_record_get` call.
  The borrow is valid while the case subject remains alive.
  """
  @spec maybe_unwrap_var_branch(
          Types.compile_env(),
          map(),
          Types.subject_ref(),
          integer(),
          Types.case_subject() | nil
        ) ::
          {Types.compile_env(), String.t(), String.t(), integer()}
  def maybe_unwrap_var_branch(env, branch, subject_ref, counter, case_subject \\ nil) do
    if Map.get(env, :maybe_unwrap_just, false) and var_branch?(branch) do
      %{pattern: %{kind: :var, name: bind}} = branch
      next = counter + 1
      temp = "tmp_#{next}"
      subject = pattern_subject_ref(subject_ref)

      setup = "ElmcValue *#{temp} = elmc_maybe_or_tuple_just_payload_borrow(#{subject});"
      release = ""

      branch_env =
        env
        |> Map.put(bind, temp)
        |> Map.delete(:maybe_unwrap_just)
        |> put_maybe_unwrapped_var_type(case_subject, bind)

      {branch_env, setup, release, next}
    else
      {bind_pattern(env, branch.pattern, subject_ref), "", "", counter}
    end
  end

  defp put_maybe_unwrapped_var_type(env, case_subject, bind) when not is_nil(case_subject) do
    subject_expr =
      case case_subject do
        name when is_binary(name) -> %{op: :var, name: name}
        expr -> expr
      end

    case Expr.maybe_unwrapped_record_type(subject_expr, env) do
      type when is_binary(type) -> EnvBindings.put_var_type(env, bind, type)
      _ -> env
    end
  end

  defp put_maybe_unwrapped_var_type(env, _case_subject, _bind), do: env

  defp put_just_bind_var_type(env, _subject_ref, bind) when bind in [nil, "", "_"], do: env

  defp put_just_bind_var_type(env, subject_ref, bind) when is_binary(bind) and is_binary(subject_ref) do
    payload_type =
      Expr.record_payload_type_for_var(env, subject_ref) ||
        Map.get(env, :__case_subject_payload_type__)

    case payload_type do
      type when is_binary(type) ->
        env
        |> EnvBindings.put_var_type(bind, type)
        |> EnvBindings.put_record_shape(bind, Expr.record_shape_from_type(type, env))

      _ ->
        env
    end
  end

  defp put_just_bind_var_type(env, _subject_ref, _bind), do: env

  @spec nothing_branch?(map()) :: boolean()
  defp nothing_branch?(%{pattern: %{kind: :constructor, name: name}})
       when name in ["Nothing", "Maybe.Nothing"],
       do: true

  defp nothing_branch?(_), do: false

  @spec var_branch?(map()) :: boolean()
  defp var_branch?(%{pattern: %{kind: :var, name: name}})
       when is_binary(name) and name not in ["_", ""],
       do: true

  defp var_branch?(_), do: false

  @spec just_payload_ref(Types.subject_ref()) :: String.t()
  defp just_payload_ref(subject_ref) do
    "elmc_maybe_or_tuple_just_payload_borrow(#{pattern_subject_ref(subject_ref)})"
  end

  @spec pattern_subject_ref(Types.subject_ref()) :: String.t()
  defp pattern_subject_ref(subject_ref) when is_binary(subject_ref), do: subject_ref
  defp pattern_subject_ref(%{op: :var, name: name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{"op" => :var, "name" => name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{name: name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{"name" => name}) when is_binary(name), do: name
  defp pattern_subject_ref(subject_ref), do: inspect(subject_ref)

  defp list_int_subject?(env, subject_ref) when is_binary(subject_ref) do
    env
    |> Map.get(:__var_types__, %{})
    |> Map.get(EnvBindings.binding_key(subject_ref))
    |> Kernel.==("List Int")
  end

  defp maybe_mark_list_int_cons(env, head, tail, true) do
    env
    |> mark_list_int_head(head)
    |> mark_list_int_tail(tail)
  end

  defp maybe_mark_list_int_cons(env, _head, _tail, _list_int?), do: env

  defp mark_list_int_head(env, %{kind: :var, name: name}) when name not in ["_", ""] do
    env
    |> EnvBindings.put_boxed_int_binding(name, true)
    |> EnvBindings.put_var_type(name, "Int")
  end

  defp mark_list_int_head(env, _pattern), do: env

  defp mark_list_int_tail(env, %{kind: :var, name: name}) when name not in ["_", ""] do
    EnvBindings.put_var_type(env, name, "List Int")
  end

  defp mark_list_int_tail(
         env,
         %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}}
       ) do
    env
    |> mark_list_int_head(head)
    |> mark_list_int_tail(tail)
  end

  defp mark_list_int_tail(env, _pattern), do: env

  @spec constructor_arg_condition(String.t(), Types.pattern()) :: String.t()
  defp constructor_arg_condition(_value_ref, %{kind: :wildcard}), do: ""
  defp constructor_arg_condition(_value_ref, %{kind: :var}), do: ""

  defp constructor_arg_condition(value_ref, arg_pattern) when is_map(arg_pattern) do
    " && (#{pattern_condition(value_ref, arg_pattern)})"
  end

  defp put_pattern_field_record_shape(env, name, shape) when is_list(shape) do
    shapes = Map.get(env, :__record_shapes__, %{})
    Map.put(env, :__record_shapes__, Map.put(shapes, EnvBindings.binding_key(name), shape))
  end

  defp put_pattern_field_record_shape(env, _name, _shape), do: env

  defp bool_constructor_name(%{resolved_name: name}) when name in ["True", "False"], do: name
  defp bool_constructor_name(%{name: name}) when name in ["True", "False"], do: name
  defp bool_constructor_name(_), do: nil

  defp bool_constructor_condition(subject_ref, true_value?) do
    bool_match =
      if true_value? do
        "((#{subject_ref})->tag == ELMC_TAG_BOOL && elmc_as_bool(#{subject_ref}))"
      else
        "((#{subject_ref})->tag == ELMC_TAG_BOOL && !elmc_as_bool(#{subject_ref}))"
      end

    int_match =
      if true_value? do
        "((#{subject_ref})->tag == ELMC_TAG_INT && elmc_as_int(#{subject_ref}) == 1)"
      else
        "((#{subject_ref})->tag == ELMC_TAG_INT && elmc_as_int(#{subject_ref}) == 0)"
      end

    "(#{subject_ref}) && (#{bool_match} || #{int_match})"
  end

  defp order_constructor_name(%{resolved_name: name}) when name in ["LT", "EQ", "GT"], do: name
  defp order_constructor_name(%{name: name}) when name in ["LT", "EQ", "GT"], do: name
  defp order_constructor_name(_), do: nil

  defp order_scalar("LT"), do: -1
  defp order_scalar("EQ"), do: 0
  defp order_scalar("GT"), do: 1

  defp order_constructor_condition(subject_ref, scalar) do
    "(#{subject_ref}) && (#{subject_ref})->tag == ELMC_TAG_ORDER && elmc_as_int(#{subject_ref}) == #{scalar}"
  end

  defp nest_tuple_pattern([left, right]) do
    %{kind: :tuple, elements: [left, right]}
  end

  defp nest_tuple_pattern([left | rest]) do
    %{kind: :tuple, elements: [left, nest_tuple_pattern(rest)]}
  end
end
