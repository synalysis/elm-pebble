defmodule Elmc.Backend.CCodegen.Patterns do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.PebbleMsgTag
  alias Elmc.Backend.CCodegen.StoragePlan
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @type list_pattern_mode :: :cons | :int_list | :int_spine | :float_list | :record_seq

  @spec pattern_condition(String.t(), Types.pattern(), Types.compile_env()) :: String.t()
  def pattern_condition(subject_ref, pattern, env \\ %{})

  def pattern_condition(_subject_ref, %{kind: :wildcard}, _env), do: "1"
  def pattern_condition(_subject_ref, %{kind: :var}, _env), do: "1"

  def pattern_condition(subject_ref, pattern, env)
      when is_map(pattern) and not is_binary(subject_ref) do
    pattern_condition(pattern_subject_ref(subject_ref), pattern, env)
  end

  def pattern_condition(subject_ref, %{kind: :int, value: value}, _env) when is_integer(value) do
    "#{subject_ref} && (#{subject_ref}->tag == ELMC_TAG_INT || #{subject_ref}->tag == ELMC_TAG_CHAR) && elmc_as_int(#{subject_ref}) == #{value}"
  end

  def pattern_condition(subject_ref, %{kind: :char, value: value}, _env) when is_integer(value) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_CHAR && elmc_as_int(#{subject_ref}) == #{value}"
  end

  def pattern_condition(subject_ref, %{kind: :tuple, elements: elements}, env)
      when is_list(elements) and length(elements) > 2 do
    pattern_condition(subject_ref, nest_tuple_pattern(elements), env)
  end

  def pattern_condition(subject_ref, %{kind: :tuple, elements: [left, right]}, env) do
    left_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->first"
    right_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_TUPLE2 && (#{pattern_condition(left_ref, left, env)}) && (#{pattern_condition(right_ref, right, env)})"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "()", arg_pattern: nil}, _env) do
    "#{subject_ref} && elmc_value_is_unit(#{subject_ref})"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "()", arg_pattern: pattern}, env)
      when not is_nil(pattern) do
    pattern_condition(subject_ref, pattern, env)
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "Ok", arg_pattern: arg_pattern}, env) do
    value_ref = "((ElmcResult *)#{subject_ref}->payload)->value"
    arg_cond = if arg_pattern, do: " && (#{pattern_condition(value_ref, arg_pattern, env)})", else: ""

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_RESULT && ((ElmcResult *)#{subject_ref}->payload)->is_ok == 1#{arg_cond}"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "Err", arg_pattern: arg_pattern}, env) do
    value_ref = "((ElmcResult *)#{subject_ref}->payload)->value"
    arg_cond = if arg_pattern, do: " && (#{pattern_condition(value_ref, arg_pattern, env)})", else: ""

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_RESULT && ((ElmcResult *)#{subject_ref}->payload)->is_ok == 0#{arg_cond}"
  end

  def pattern_condition(subject_ref, %{
        kind: :constructor,
        name: "Just",
        arg_pattern: arg_pattern
      }, env) do
    maybe_value_ref = "((ElmcMaybe *)#{subject_ref}->payload)->value"
    tuple_value_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"

    maybe_arg_cond =
      if arg_pattern, do: " && (#{pattern_condition(maybe_value_ref, arg_pattern, env)})", else: ""

    tuple_arg_cond =
      if arg_pattern, do: " && (#{pattern_condition(tuple_value_ref, arg_pattern, env)})", else: ""

    maybe_cond =
      "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)#{subject_ref}->payload)->is_just == 1#{maybe_arg_cond}"

    tuple_cond =
      "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_TUPLE2 && #{subject_ref}->payload != NULL && elmc_as_int(((ElmcTuple2 *)#{subject_ref}->payload)->first) == 1#{tuple_arg_cond}"

    "((#{maybe_cond}) || (#{tuple_cond}))"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "Nothing"}, _env) do
    maybe_cond =
      "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)#{subject_ref}->payload)->is_just == 0"

    int_cond =
      "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_INT && elmc_as_int(#{subject_ref}) == 0"

    "((#{maybe_cond}) || (#{int_cond}))"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "[]"}, env) do
    env
    |> list_pattern_modes(subject_ref)
    |> Enum.map(&list_empty_condition(&1, subject_ref))
    |> or_join()
  end

  def pattern_condition(subject_ref, %{
        kind: :constructor,
        name: "::",
        arg_pattern: %{kind: :tuple, elements: [head_pattern, tail_pattern]}
      }, env) do
    env
    |> list_pattern_modes(subject_ref)
    |> Enum.map(
      &list_cons_condition(&1, subject_ref, head_pattern, tail_pattern, env)
    )
    |> or_join()
  end

  def pattern_condition(subject_ref, %{kind: :constructor, name: "::"}, env) do
    env
    |> list_pattern_modes(subject_ref)
    |> Enum.map(&list_nonempty_condition(&1, subject_ref))
    |> or_join()
  end

  def pattern_condition(_subject_ref, %{kind: :record}, _env) do
    "1"
  end

  def pattern_condition(subject_ref, %{kind: :string, value: value}, _env) when is_binary(value) do
    escaped = Util.escape_c_string(value)

    "#{subject_ref} && elmc_string_equals_cstr(#{subject_ref}, \"#{escaped}\")"
  end

  def pattern_condition(
        subject_ref,
        %{kind: :constructor, tag: tag, arg_pattern: arg_pattern} = pattern,
        env
      )
      when is_integer(tag) and is_map(arg_pattern) do
    tag_ref = PebbleMsgTag.tag_expr(pattern)
    value_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"
    arg_cond = constructor_arg_condition(value_ref, arg_pattern, env)

    tagged_match =
      "((#{subject_ref})->tag == ELMC_TAG_TUPLE2 && (#{subject_ref})->payload != NULL && elmc_as_int(((ElmcTuple2 *)(#{subject_ref})->payload)->first) == #{tag_ref}#{arg_cond})"

    "(#{subject_ref}) && #{tagged_match}"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, tag: tag} = pattern, _env)
      when is_integer(tag) do
    tag_ref = PebbleMsgTag.tag_expr(pattern)

    int_match =
      "((#{subject_ref})->tag == ELMC_TAG_INT && elmc_as_int(#{subject_ref}) == #{tag_ref})"

    tuple_match =
      "((#{subject_ref})->tag == ELMC_TAG_TUPLE2 && (#{subject_ref})->payload != NULL && elmc_as_int(((ElmcTuple2 *)(#{subject_ref})->payload)->first) == #{tag_ref})"

    "(#{subject_ref}) && (#{int_match} || #{tuple_match})"
  end

  def pattern_condition(subject_ref, %{kind: :constructor} = pattern, _env) do
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

  def pattern_condition(_subject_ref, _pattern, _env), do: "0"

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

    {head_ref, tail_ref} = list_cons_binding_refs(subject_ref, list_int?)

    env
    |> bind_pattern(head, head_ref)
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
          Types.case_branch(),
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

  @spec put_maybe_unwrapped_var_type(
          Types.compile_env(),
          Types.case_subject(),
          String.t()
        ) :: Types.compile_env()
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

  @spec put_just_bind_var_type(Types.compile_env(), Types.subject_ref(), String.t() | nil) ::
          Types.compile_env()
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

  @spec list_int_subject?(Types.compile_env(), String.t()) :: boolean()
  defp list_int_subject?(env, subject_ref) when is_binary(subject_ref) do
    cond do
      int_list_access_expr?(subject_ref) or int_spine_access_expr?(subject_ref) ->
        true

      true ->
        list_subject_type(env, subject_ref) == "List Int"
    end
  end

  defp list_subject_type(env, subject_ref) when is_binary(subject_ref) do
    env
    |> Map.get(:__var_types__, %{})
    |> Map.get(EnvBindings.binding_key(simple_binding_name(subject_ref) || subject_ref))
  end

  @spec int_list_access_expr?(String.t()) :: boolean()
  defp int_list_access_expr?(subject_ref) do
    String.contains?(subject_ref, "elmc_int_list_tail_take") or
      String.contains?(subject_ref, "elmc_int_list_head_boxed") or
      String.contains?(subject_ref, "elmc_int_spine_tail_take") or
      String.contains?(subject_ref, "elmc_int_spine_head_boxed")
  end

  @spec list_cons_binding_refs(String.t(), boolean()) :: {String.t(), String.t()}
  defp list_cons_binding_refs(subject_ref, true) do
    {"elmc_int_list_head_boxed(#{subject_ref})", "elmc_int_list_tail_take(#{subject_ref})"}
  end

  defp list_cons_binding_refs(subject_ref, false) do
    {"((ElmcCons *)#{subject_ref}->payload)->head", "((ElmcCons *)#{subject_ref}->payload)->tail"}
  end

  @spec maybe_mark_list_int_cons(Types.compile_env(), Types.pattern(), Types.pattern(), boolean()) ::
          Types.compile_env()
  defp maybe_mark_list_int_cons(env, head, tail, true) do
    env
    |> mark_list_int_head(head)
    |> mark_list_int_tail(tail)
  end

  defp maybe_mark_list_int_cons(env, _head, _tail, _list_int?), do: env

  @spec mark_list_int_head(Types.compile_env(), Types.pattern()) :: Types.compile_env()
  defp mark_list_int_head(env, %{kind: :var, name: name}) when name not in ["_", ""] do
    env
    |> EnvBindings.put_boxed_int_binding(name, true)
    |> EnvBindings.put_var_type(name, "Int")
  end

  defp mark_list_int_head(env, _pattern), do: env

  @spec mark_list_int_tail(Types.compile_env(), Types.pattern()) :: Types.compile_env()
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

  defp or_join([]), do: "0"
  defp or_join(conditions), do: "(" <> Enum.map_join(conditions, " || ", &"(#{&1})") <> ")"

  defp list_empty_condition(:cons, subject_ref) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_LIST && #{subject_ref}->payload == NULL"
  end

  defp list_empty_condition(:int_list, subject_ref) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_INT_LIST && elmc_int_list_is_empty(#{subject_ref})"
  end

  defp list_empty_condition(:int_spine, subject_ref) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_INT_SPINE && elmc_int_spine_is_empty(#{subject_ref})"
  end

  defp list_empty_condition(:float_list, subject_ref) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_FLOAT_LIST && elmc_float_list_is_empty(#{subject_ref})"
  end

  defp list_empty_condition(:record_seq, subject_ref) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_RECORD_SEQ && elmc_record_seq_is_empty(#{subject_ref})"
  end

  defp list_nonempty_condition(:cons, subject_ref) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_LIST && #{subject_ref}->payload != NULL"
  end

  defp list_nonempty_condition(:int_list, subject_ref) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_INT_LIST && !elmc_int_list_is_empty(#{subject_ref})"
  end

  defp list_nonempty_condition(:int_spine, subject_ref) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_INT_SPINE && !elmc_int_spine_is_empty(#{subject_ref})"
  end

  defp list_nonempty_condition(:float_list, subject_ref) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_FLOAT_LIST && !elmc_float_list_is_empty(#{subject_ref})"
  end

  defp list_nonempty_condition(:record_seq, subject_ref) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_RECORD_SEQ && !elmc_record_seq_is_empty(#{subject_ref})"
  end

  defp list_cons_condition(mode, subject_ref, head_pattern, tail_pattern, env) do
    {head_ref, tail_ref} = list_head_tail_refs(mode, subject_ref)

    "#{list_nonempty_condition(mode, subject_ref)} && (#{pattern_condition(head_ref, head_pattern, env)}) && (#{pattern_condition(tail_ref, tail_pattern, env)})"
  end

  defp list_head_tail_refs(:cons, subject_ref) do
    {"((ElmcCons *)#{subject_ref}->payload)->head", "((ElmcCons *)#{subject_ref}->payload)->tail"}
  end

  defp list_head_tail_refs(:int_list, subject_ref) do
    {"elmc_int_list_head_boxed(#{subject_ref})", "elmc_int_list_tail_take(#{subject_ref})"}
  end

  defp list_head_tail_refs(:int_spine, subject_ref) do
    {"elmc_int_spine_head_boxed(#{subject_ref})", "elmc_int_spine_tail_take(#{subject_ref})"}
  end

  defp list_head_tail_refs(:float_list, subject_ref) do
    {"elmc_float_list_head_boxed(#{subject_ref})", "elmc_float_list_tail_take(#{subject_ref})"}
  end

  defp list_head_tail_refs(:record_seq, subject_ref) do
    {"elmc_record_seq_head_boxed(#{subject_ref})", "elmc_record_seq_tail_take(#{subject_ref})"}
  end

  @spec list_pattern_modes(Types.compile_env(), String.t()) :: [list_pattern_mode()]
  defp list_pattern_modes(env, subject_ref) do
    plan = list_subject_plan(env, subject_ref)

    cond do
      int_spine_access_expr?(subject_ref) ->
        [:int_spine]

      int_list_access_expr?(subject_ref) ->
        [:int_list]

      match?(%StoragePlan{elem: {:primitive, :int}}, plan) ->
        int_modes_from_plan(plan)

      match?(%StoragePlan{elem: {:primitive, :float}}, plan) ->
        float_modes_from_plan(plan)

      match?(%StoragePlan{elem: {:record, _, _}}, plan) ->
        record_modes_from_plan(plan)

      list_subject_type(env, subject_ref) == "List Int" ->
        int_modes_from_plan(plan)

      list_subject_type(env, subject_ref) == "List Float" ->
        float_modes_from_plan(plan)

      true ->
        [:cons]
    end
  end

  defp int_modes_from_plan(%StoragePlan{layout: :compact, elem: {:primitive, :int}}), do: [:int_list]
  defp int_modes_from_plan(%StoragePlan{layout: :native_linked, elem: {:primitive, :int}}), do: [:int_spine]

  defp int_modes_from_plan(%StoragePlan{layout: :boxed_cons, elem: {:primitive, :int}}),
    do: [:cons]

  defp int_modes_from_plan(_), do: [:int_list, :int_spine, :cons]

  defp float_modes_from_plan(%StoragePlan{layout: :compact, elem: {:primitive, :float}}),
    do: [:float_list]

  defp float_modes_from_plan(_), do: [:float_list, :cons]

  defp record_modes_from_plan(%StoragePlan{layout: :compact, elem: {:record, _, _}}),
    do: [:record_seq]

  defp record_modes_from_plan(_), do: [:record_seq, :cons]

  defp list_subject_plan(env, subject_ref) do
    with name when is_binary(name) <- simple_binding_name(subject_ref),
         mod when is_binary(mod) <- Map.get(env, :__module__),
         fun when is_binary(fun) <- Map.get(env, :__function_name__) do
      key = {mod, fun, name}
      storage = Process.get(:elmc_storage_plans, %{})

      case Map.get(storage, :binding_plans, %{}) |> Map.get(key) do
        %StoragePlan{} = plan -> plan
        _ -> Map.get(storage |> Map.get(:param_plans, %{}), key, StoragePlan.mixed())
      end
    else
      _ -> StoragePlan.mixed()
    end
  end

  defp simple_binding_name(subject_ref) when is_binary(subject_ref) do
    if Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, subject_ref), do: subject_ref, else: nil
  end

  defp simple_binding_name(_), do: nil

  @spec int_spine_access_expr?(String.t()) :: boolean()
  defp int_spine_access_expr?(subject_ref) do
    String.contains?(subject_ref, "elmc_int_spine_tail_take") or
      String.contains?(subject_ref, "elmc_int_spine_head_boxed")
  end

  @spec constructor_arg_condition(String.t(), Types.pattern(), Types.compile_env()) :: String.t()
  defp constructor_arg_condition(_value_ref, %{kind: :wildcard}, _env), do: ""
  defp constructor_arg_condition(_value_ref, %{kind: :var}, _env), do: ""

  defp constructor_arg_condition(value_ref, arg_pattern, env) when is_map(arg_pattern) do
    " && (#{pattern_condition(value_ref, arg_pattern, env)})"
  end

  defp constructor_arg_condition(_value_ref, _arg_pattern, _env), do: ""

  @spec put_pattern_field_record_shape(
          Types.compile_env(),
          String.t(),
          Types.record_field_names() | term()
        ) :: Types.compile_env()
  defp put_pattern_field_record_shape(env, name, shape) when is_list(shape) do
    shapes = Map.get(env, :__record_shapes__, %{})
    Map.put(env, :__record_shapes__, Map.put(shapes, EnvBindings.binding_key(name), shape))
  end

  defp put_pattern_field_record_shape(env, _name, _shape), do: env

  @spec bool_constructor_name(Types.pattern() | map()) :: String.t() | nil
  defp bool_constructor_name(%{resolved_name: name}) when name in ["True", "False"], do: name
  defp bool_constructor_name(%{name: name}) when name in ["True", "False"], do: name
  defp bool_constructor_name(_), do: nil

  @spec bool_constructor_condition(String.t(), boolean()) :: String.t()
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

  @spec order_constructor_name(Types.pattern() | map()) :: String.t() | nil
  defp order_constructor_name(%{resolved_name: name}) when name in ["LT", "EQ", "GT"], do: name
  defp order_constructor_name(%{name: name}) when name in ["LT", "EQ", "GT"], do: name
  defp order_constructor_name(_), do: nil

  @spec order_scalar(String.t()) :: -1 | 0 | 1
  defp order_scalar("LT"), do: -1
  defp order_scalar("EQ"), do: 0
  defp order_scalar("GT"), do: 1

  @spec order_constructor_condition(String.t(), integer()) :: String.t()
  defp order_constructor_condition(subject_ref, scalar) do
    "(#{subject_ref}) && (#{subject_ref})->tag == ELMC_TAG_ORDER && elmc_as_int(#{subject_ref}) == #{scalar}"
  end

  @spec nest_tuple_pattern([Types.pattern()]) :: Types.pattern()
  defp nest_tuple_pattern([left, right]) do
    %{kind: :tuple, elements: [left, right]}
  end

  defp nest_tuple_pattern([left | rest]) do
    %{kind: :tuple, elements: [left, nest_tuple_pattern(rest)]}
  end
end
