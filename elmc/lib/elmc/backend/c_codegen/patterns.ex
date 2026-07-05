defmodule Elmc.Backend.CCodegen.Patterns do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.Native.RecordFields
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.StoragePlan
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.UnionMacros
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.ValueSlots

  @type list_pattern_mode :: :cons | :int_list | :int_spine | :float_list | :record_seq

  @spec pattern_condition(String.t(), Types.pattern(), Types.compile_env()) :: String.t()
  def pattern_condition(subject_ref, pattern, env \\ %{})

  def pattern_condition(subject_ref, pattern, env) when is_binary(subject_ref) do
    pattern_condition_for(RcRuntimeEmit.value_expr(subject_ref), pattern, env)
  end

  def pattern_condition(subject_ref, pattern, env) do
    pattern_condition_for(pattern_subject_ref(subject_ref), pattern, env)
  end

  defp pattern_condition_for(_subject_ref, %{kind: :wildcard}, _env), do: "1"
  defp pattern_condition_for(_subject_ref, %{kind: :var}, _env), do: "1"

  defp pattern_condition_for(subject_ref, %{kind: :int, value: value}, _env) when is_integer(value) do
    "#{subject_ref} && (#{subject_ref}->tag == ELMC_TAG_INT || #{subject_ref}->tag == ELMC_TAG_CHAR) && elmc_as_int(#{subject_ref}) == #{value}"
  end

  defp pattern_condition_for(subject_ref, %{kind: :char, value: value}, _env) when is_integer(value) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_CHAR && elmc_as_int(#{subject_ref}) == #{value}"
  end

  defp pattern_condition_for(subject_ref, %{kind: :tuple, elements: elements}, env)
      when is_list(elements) and length(elements) > 2 do
    pattern_condition(subject_ref, nest_tuple_pattern(elements), env)
  end

  defp pattern_condition_for(subject_ref, %{kind: :tuple, elements: [left, right]}, env) do
    left_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->first"
    right_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_TUPLE2 && (#{pattern_condition(left_ref, left, env)}) && (#{pattern_condition(right_ref, right, env)})"
  end

  defp pattern_condition_for(subject_ref, %{kind: :constructor, name: "()", arg_pattern: nil}, _env) do
    "#{subject_ref} && elmc_value_is_unit(#{subject_ref})"
  end

  defp pattern_condition_for(subject_ref, %{kind: :constructor, name: "()", arg_pattern: pattern}, env)
      when not is_nil(pattern) do
    pattern_condition(subject_ref, pattern, env)
  end

  defp pattern_condition_for(subject_ref, %{kind: :constructor, name: "Ok", arg_pattern: arg_pattern}, env) do
    value_ref = "((ElmcResult *)#{subject_ref}->payload)->value"
    arg_cond = if arg_pattern, do: " && (#{pattern_condition(value_ref, arg_pattern, env)})", else: ""

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_RESULT && ((ElmcResult *)#{subject_ref}->payload)->is_ok == 1#{arg_cond}"
  end

  defp pattern_condition_for(subject_ref, %{kind: :constructor, name: "Err", arg_pattern: arg_pattern}, env) do
    value_ref = "((ElmcResult *)#{subject_ref}->payload)->value"
    arg_cond = if arg_pattern, do: " && (#{pattern_condition(value_ref, arg_pattern, env)})", else: ""

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_RESULT && ((ElmcResult *)#{subject_ref}->payload)->is_ok == 0#{arg_cond}"
  end

  defp pattern_condition_for(subject_ref, %{
        kind: :constructor,
        name: "Just",
        arg_pattern: arg_pattern
      }, env) do
    cond do
      just_arg_is_true?(arg_pattern) ->
        "elmc_maybe_just_true(#{subject_ref})"

      just_arg_is_false?(arg_pattern) ->
        "elmc_maybe_just_false(#{subject_ref})"

      bare_just_pattern?(arg_pattern) ->
        "elmc_maybe_is_just(#{subject_ref})"

      true ->
        payload_expr = "elmc_maybe_just_payload(#{subject_ref})"
        arg_cond = pattern_condition(payload_expr, arg_pattern, env)
        "(#{payload_expr}) && (#{arg_cond})"
    end
  end

  defp pattern_condition_for(subject_ref, %{kind: :constructor, name: "Nothing"}, _env) do
    "elmc_maybe_is_nothing(#{subject_ref})"
  end

  defp pattern_condition_for(subject_ref, %{kind: :constructor, name: "[]"}, env) do
    env
    |> list_pattern_modes(subject_ref)
    |> Enum.map(&list_empty_condition(&1, subject_ref))
    |> or_join()
  end

  defp pattern_condition_for(subject_ref, %{
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

  defp pattern_condition_for(subject_ref, %{kind: :constructor, name: "::"}, env) do
    env
    |> list_pattern_modes(subject_ref)
    |> Enum.map(&list_nonempty_condition(&1, subject_ref))
    |> or_join()
  end

  defp pattern_condition_for(_subject_ref, %{kind: :record}, _env) do
    "1"
  end

  defp pattern_condition_for(subject_ref, %{kind: :string, value: value}, _env) when is_binary(value) do
    escaped = Util.escape_c_string(value)

    "#{subject_ref} && elmc_string_equals_cstr(#{subject_ref}, \"#{escaped}\")"
  end

  defp pattern_condition_for(subject_ref, %{kind: :constructor, arg_pattern: arg_pattern} = pattern, env)
      when is_map(arg_pattern) do
    case pattern_tag_expr(pattern, env) do
      tag when is_binary(tag) ->
        value_ref = union_constructor_payload_ref(subject_ref)
        arg_cond = constructor_arg_condition(value_ref, arg_pattern, env)

        "elmc_union_tag_matches(#{subject_ref}, #{tag})#{arg_cond}"

      _ ->
        pattern_condition_fallback_constructor(subject_ref, pattern, env)
    end
  end

  defp pattern_condition_for(subject_ref, %{kind: :constructor} = pattern, env) do
    case pattern_tag_expr(pattern, env) do
      tag when is_binary(tag) ->
        "elmc_union_tag_matches(#{subject_ref}, #{tag})"

      _ ->
        pattern_condition_fallback_constructor(subject_ref, pattern, env)
    end
  end

  defp pattern_condition_for(_subject_ref, _pattern, _env), do: "0"

  defp pattern_condition_fallback_constructor(subject_ref, pattern, _env) do
    case order_constructor_name(pattern) do
      name when name in ["LT", "EQ", "GT"] ->
        order_constructor_condition(subject_ref, order_scalar(name))

      _ ->
        case bool_constructor_name(pattern) do
          "False" -> "elmc_value_is_false(#{subject_ref})"
          "True" -> "elmc_value_is_true(#{subject_ref})"
          _ -> "0"
        end
    end
  end

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

    env
    |> Map.put(bind, ref)
    |> then(fn e ->
      if Map.get(env, :maybe_unwrap_just), do: EnvBindings.put_tuple_projection_ref(e, ref), else: e
    end)
    |> then(fn e ->
      if Map.get(env, :maybe_unwrap_just), do: put_just_bind_var_type(e, subject_ref, bind), else: e
    end)
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
      |> then(fn branch_env ->
        if is_binary(bind), do: EnvBindings.put_tuple_projection_ref(branch_env, value_ref), else: branch_env
      end)
      |> put_just_bind_var_type(subject_ref, bind)

    if arg, do: bind_pattern(env, arg, value_ref), else: env
  end

  def bind_pattern(
        env,
        %{
          kind: :constructor,
          name: "::",
          arg_pattern: %{kind: :tuple, elements: [head, tail]}
        } = pattern,
        subject_ref
      ) do
    bind = Map.get(pattern, :bind)
    subject_ref = pattern_subject_ref(subject_ref)
    list_int? = list_int_subject?(env, subject_ref)
    env = if is_binary(bind), do: Map.put(env, bind, subject_ref), else: env

    if list_int? and RcRuntimeEmit.rc_allocator_emit_mode?(env) do
      counter = Map.get(env, :__bind_counter__, 0)

      branch = %{
        pattern: %{
          kind: :constructor,
          name: "::",
          bind: bind,
          arg_pattern: %{kind: :tuple, elements: [head, tail]}
        }
      }

      {branch_env, setup, cleanup, counter} =
        hoist_int_list_cons_branch(env, branch, subject_ref, counter)

      branch_env
      |> Map.put(:__bind_counter__, counter)
      |> put_pattern_bind_setup(setup)
      |> put_pattern_bind_cleanup(cleanup)
    else
      {head_ref, tail_ref} = list_cons_binding_refs(subject_ref, list_int?)

      env
      |> bind_pattern(head, head_ref)
      |> bind_pattern(tail, tail_ref)
      |> EnvBindings.put_list_suffix_ref(tail_ref)
      |> maybe_mark_list_int_cons(head, tail, list_int?)
    end
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
        %{kind: :constructor, bind: bind, arg_pattern: arg} = pattern,
        subject_ref
      ) do
    case constructor_pattern_tag(pattern) do
      tag when is_integer(tag) -> bind_constructor_tag_pattern(env, pattern, bind, arg, subject_ref)
      _ -> bind_pattern_fallback(env, pattern, subject_ref)
    end
  end

  def bind_pattern(env, _pattern, _subject_ref), do: env

  defp bind_constructor_tag_pattern(env, pattern, bind, arg, subject_ref) do
    subject_ref = pattern_subject_ref(subject_ref)
    tuple_payload_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"

    env =
      if is_binary(bind) do
        case Map.get(env, :__var_types__, %{}) |> Map.get(bind) do
          "Int" ->
            payload_ref = union_payload_ref(subject_ref)

            env
            |> EnvBindings.put_native_int_binding(bind, payload_ref)
            |> Map.put(bind, payload_ref)

          _ ->
            env
            |> Map.put(bind, tuple_payload_ref)
            |> put_constructor_payload_record_type(pattern, bind)
        end
      else
        env
      end

    if arg, do: bind_union_ctor_arg(env, pattern, arg, subject_ref), else: env
  end

  defp put_constructor_payload_record_type(env, pattern, bind) do
    case constructor_payload_record_type(pattern) |> normalize_payload_record_type() do
      type when is_binary(type) and type != "" ->
        env
        |> EnvBindings.put_var_type(bind, type)
        |> EnvBindings.put_record_shape(bind, Expr.record_shape_from_type(type, env))

      _ ->
        env
    end
  end

  defp normalize_payload_record_type(type) when is_binary(type) do
    case type do
      "PebbleCmd." <> rest -> "Pebble.Cmd." <> rest
      other -> other
    end
  end

  defp normalize_payload_record_type(_), do: nil

  defp constructor_payload_record_type(pattern) do
    names =
      [
        Map.get(pattern, :resolved_name),
        Map.get(pattern, :name)
      ]
      |> Enum.filter(&is_binary/1)
      |> Enum.flat_map(fn name ->
        short = name |> String.split(".") |> List.last()
        [name, short]
      end)
      |> Enum.uniq()

    payload_specs = Process.get(:elmc_msg_constructor_payload_specs, %{})

    Enum.find_value(names, fn name -> Map.get(payload_specs, name) end)
  end

  defp constructor_pattern_tag(%{tag: tag}) when is_integer(tag), do: tag
  defp constructor_pattern_tag(%{union_tag: tag}) when is_integer(tag), do: tag

  defp constructor_pattern_tag(%{kind: :constructor} = pattern) do
    lookup_ir_constructor_tag(pattern)
  end

  defp pattern_tag_expr(pattern, env) do
    case constructor_pattern_tag(pattern) do
      tag when is_integer(tag) ->
        case union_ctor_tag_ref(pattern, tag, env) do
          ref when is_binary(ref) -> ref
          _ -> Integer.to_string(tag)
        end

      _ ->
        nil
    end
  end

  defp union_ctor_tag_ref(pattern, tag, env) do
    macros = Process.get(:elmc_union_constructor_macros, %{})

    [Map.get(pattern, :resolved_name), union_pattern_ctor_name(pattern, env)]
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.find_value(fn ctor ->
      UnionMacros.literal_ref(%{op: :int_literal, value: tag, union_ctor: ctor}, env) ||
        Map.get(macros, ctor)
    end)
  end

  defp union_pattern_ctor_name(pattern, env) do
    name =
      cond do
        is_binary(Map.get(pattern, :resolved_name)) -> Map.get(pattern, :resolved_name)
        is_binary(Map.get(pattern, :name)) -> Map.get(pattern, :name)
        true -> nil
      end

    qualify_union_ctor_name(name, env)
  end

  defp qualify_union_ctor_name(name, _env) when is_binary(name) do
    if String.contains?(name, ".") do
      name
    else
      unique_qualified_union_ctor(name) || name
    end
  end

  defp qualify_union_ctor_name(_name, _env), do: nil

  defp unique_qualified_union_ctor(short_name) when is_binary(short_name) do
    tags = Process.get(:elmc_constructor_tags, %{})

    matches =
      tags
      |> Map.keys()
      |> Enum.filter(fn key -> String.ends_with?(key, "." <> short_name) end)

    case matches do
      [qualified] -> qualified
      _ -> nil
    end
  end

  defp lookup_ir_constructor_tag(%{resolved_name: name}) when is_binary(name),
    do: lookup_ir_constructor_tag_by_name(name)

  defp lookup_ir_constructor_tag(%{name: name}) when is_binary(name),
    do: lookup_ir_constructor_tag_by_name(name)

  defp lookup_ir_constructor_tag(_), do: nil

  defp lookup_ir_constructor_tag_by_name(name) when is_binary(name) do
    tags = Process.get(:elmc_constructor_tags, %{})

    cond do
      Map.has_key?(tags, name) ->
        Map.get(tags, name)

      true ->
        short = name |> String.split(".") |> List.last()

        case Map.get(tags, short) do
          tag when is_integer(tag) ->
            tag

          _ ->
            tags
            |> Enum.filter(fn {key, _tag} -> String.ends_with?(key, "." <> short) end)
            |> case do
              [{_key, tag}] -> tag
              _ -> nil
            end
        end
    end
  end

  defp bind_pattern_fallback(env, %{arg_pattern: arg} = pattern, subject_ref) when not is_nil(arg) do
    bind_union_ctor_arg(env, pattern, arg, subject_ref)
  end

  defp bind_pattern_fallback(env, _pattern, _subject_ref), do: env

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
    if int_list_cons_branch?(env, subject_ref, branch) do
      hoist_int_list_cons_branch(env, branch, subject_ref, counter)
    else
      maybe_unwrap_just_var_branch(env, branch, subject_ref, counter, case_subject)
    end
  end

  @doc false
  @spec case_branch_bindings(
          Types.compile_env(),
          Types.case_branch(),
          Types.subject_ref(),
          integer(),
          Types.case_subject() | nil
        ) ::
          {Types.compile_env(), String.t(), String.t(), integer()}
  def case_branch_bindings(env, branch, subject_ref, counter, case_subject \\ nil) do
    maybe_unwrap_var_branch(env, branch, subject_ref, counter, case_subject)
  end

  defp maybe_unwrap_just_var_branch(env, branch, subject_ref, counter, case_subject) do
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
        |> EnvBindings.put_tuple_projection_ref(temp)
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

    payload_type =
      Map.get(env, :__case_subject_payload_type__) ||
        case Expr.maybe_unwrapped_record_type(subject_expr, env) do
          type when is_binary(type) -> type
          _ -> nil
        end

    case payload_type do
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
      Map.get(env, :__case_subject_payload_type__) ||
        Expr.record_payload_type_for_var(env, subject_ref)

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
  defp pattern_subject_ref(subject_ref) when is_binary(subject_ref),
    do: RcRuntimeEmit.value_expr(subject_ref)
  defp pattern_subject_ref(%{op: :var, name: name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{"op" => :var, "name" => name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{name: name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{"name" => name}) when is_binary(name), do: name
  defp pattern_subject_ref(subject_ref), do: inspect(subject_ref)

  defp union_payload_ref(subject_ref) when is_binary(subject_ref) do
    "elmc_union_payload_int(#{pattern_subject_ref(subject_ref)})"
  end

  # Union constructors store their fields in the tuple2 payload (tag is ->first).
  defp union_constructor_payload_ref(subject_ref) when is_binary(subject_ref) do
    "((ElmcTuple2 *)#{pattern_subject_ref(subject_ref)}->payload)->second"
  end

  defp bind_union_ctor_arg(env, pattern, %{kind: :var, name: name}, subject_ref)
       when is_binary(name) do
    case constructor_payload_record_type(pattern) do
      "Int" ->
        payload_ref = union_payload_ref(subject_ref)

        env
        |> EnvBindings.put_native_int_binding(name, payload_ref)
        |> Map.put(name, payload_ref)

      type when is_binary(type) ->
        payload_ref = union_constructor_payload_ref(subject_ref)
        type = normalize_payload_record_type(type)

        env
        |> Map.put(name, payload_ref)
        |> EnvBindings.put_var_type(name, type)
        |> EnvBindings.put_record_shape(name, Expr.record_shape_from_type(type, env))

      _ ->
        payload_ref = union_payload_ref(subject_ref)

        env
        |> EnvBindings.put_native_int_binding(name, payload_ref)
        |> Map.put(name, payload_ref)
    end
  end

  defp bind_union_ctor_arg(env, _pattern, arg, subject_ref),
    do: bind_pattern(env, arg, union_constructor_payload_ref(subject_ref))

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
      String.contains?(subject_ref, "elmc_int_list_head_boxed_take") or
      String.contains?(subject_ref, "elmc_int_spine_tail_take") or
      String.contains?(subject_ref, "elmc_int_spine_head_boxed_take")
  end

  @spec list_cons_binding_refs(String.t(), boolean()) :: {String.t(), String.t()}
  defp list_cons_binding_refs(subject_ref, true) do
    {"elmc_int_list_head_boxed_take(#{subject_ref})", "elmc_int_list_tail_take(#{subject_ref})"}
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

  defp list_cons_condition(:int_list, subject_ref, head_pattern, tail_pattern, env) do
    int_list_cons_condition(subject_ref, head_pattern, tail_pattern, 0, env)
  end

  defp list_cons_condition(mode, subject_ref, head_pattern, tail_pattern, env) do
    cond do
      mode == :int_spine and RcRuntimeEmit.rc_allocator_emit_mode?(env) ->
        int_spine_cons_condition(subject_ref, head_pattern, tail_pattern, env)

      mode == :float_list and RcRuntimeEmit.rc_allocator_emit_mode?(env) ->
        float_list_cons_condition(subject_ref, head_pattern, tail_pattern, 0, env)

      mode == :record_seq and RcRuntimeEmit.rc_allocator_emit_mode?(env) ->
        record_seq_cons_condition(subject_ref, head_pattern, tail_pattern, 0, env)

      true ->
        legacy_list_cons_condition(mode, subject_ref, head_pattern, tail_pattern, env)
    end
  end

  defp legacy_list_cons_condition(mode, subject_ref, head_pattern, tail_pattern, env) do
    {head_ref, tail_ref} = list_head_tail_refs(mode, subject_ref)

    "#{list_nonempty_condition(mode, subject_ref)} && (#{pattern_condition(head_ref, head_pattern, env)}) && (#{pattern_condition(tail_ref, tail_pattern, env)})"
  end

  defp list_head_tail_refs(:cons, subject_ref) do
    {"((ElmcCons *)#{subject_ref}->payload)->head", "((ElmcCons *)#{subject_ref}->payload)->tail"}
  end

  defp list_head_tail_refs(:int_spine, subject_ref) do
    {"elmc_int_spine_head_boxed_take(#{subject_ref})", "elmc_int_spine_tail_take(#{subject_ref})"}
  end

  defp list_head_tail_refs(:float_list, subject_ref) do
    {"elmc_float_list_head_boxed_take(#{subject_ref})", "elmc_float_list_tail_take(#{subject_ref})"}
  end

  defp list_head_tail_refs(:record_seq, subject_ref) do
    {"elmc_record_seq_head_boxed_take(#{subject_ref})", "elmc_record_seq_tail_take(#{subject_ref})"}
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
      String.contains?(subject_ref, "elmc_int_spine_head_boxed_take")
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

  defp just_arg_is_true?(pattern), do: bool_constructor_name(pattern) == "True"
  defp just_arg_is_false?(pattern), do: bool_constructor_name(pattern) == "False"
  defp bare_just_pattern?(nil), do: true
  defp bare_just_pattern?(%{kind: :wildcard}), do: true
  defp bare_just_pattern?(%{kind: :var}), do: true
  defp bare_just_pattern?(_), do: false

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

  @doc false
  @spec pattern_bind_setup(Types.compile_env()) :: String.t()
  def pattern_bind_setup(env), do: Map.get(env, :__pattern_bind_setup__, "")

  @doc false
  @spec pattern_bind_cleanup(Types.compile_env()) :: String.t()
  def pattern_bind_cleanup(env), do: Map.get(env, :__pattern_bind_cleanup__, "")

  defp put_pattern_bind_setup(env, ""), do: env

  defp put_pattern_bind_setup(env, setup) when is_binary(setup) do
    Map.put(env, :__pattern_bind_setup__, setup)
  end

  defp put_pattern_bind_cleanup(env, ""), do: env

  defp put_pattern_bind_cleanup(env, cleanup) when is_binary(cleanup) do
    Map.put(env, :__pattern_bind_cleanup__, cleanup)
  end

  @list_case_suffix_var ~r/^list_case_suffix_\d+$/

  defp int_list_cons_branch?(env, subject_ref, %{pattern: pattern}) do
    list_int_subject?(env, subject_ref) and cons_pattern?(pattern)
  end

  defp int_list_cons_branch?(_env, _subject_ref, _branch), do: false

  defp cons_pattern?(%{kind: :constructor, name: "::"}), do: true
  defp cons_pattern?(_), do: false

  defp hoist_int_list_cons_branch(env, %{pattern: pattern}, subject_ref, counter) do
    subject = pattern_subject_ref(subject_ref)

    {branch_env, setup_lines, cleanup_vars, counter} =
      walk_int_list_cons_pattern(env, pattern, subject, 0, counter, [], [])

    setup = Enum.join(setup_lines, "\n")
    cleanup = cleanup_vars |> Enum.uniq() |> Enum.map_join("\n", &ValueSlots.release_consumed/1)
    {branch_env, setup, cleanup, counter}
  end

  defp walk_int_list_cons_pattern(
         env,
         %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}},
         subject,
         index,
         counter,
         setup,
         cleanup
       ) do
    env = bind_int_list_head_pattern(env, head, subject, index)
    walk_int_list_cons_pattern(env, tail, subject, index + 1, counter, setup, cleanup)
  end

  defp walk_int_list_cons_pattern(env, %{kind: :constructor, name: "[]"}, _subject, _index, counter, setup, cleanup) do
    {env, setup, cleanup, counter}
  end

  defp walk_int_list_cons_pattern(
         env,
         %{kind: :var, name: bind},
         subject,
         index,
         counter,
         setup,
         cleanup
       )
       when bind not in ["", "_"] do
    counter = counter + 1
    var = "list_case_suffix_#{counter}"
    stmt = int_list_suffix_hoist_stmt(var, index, subject, env)
    env =
      env
      |> Map.put(bind, var)
      |> EnvBindings.put_list_suffix_ref(var)
      |> EnvBindings.put_var_type(bind, "List Int")

    {env, [stmt | setup], [var | cleanup], counter}
  end

  defp walk_int_list_cons_pattern(env, %{kind: :wildcard}, _subject, _index, counter, setup, cleanup) do
    {env, setup, cleanup, counter}
  end

  defp walk_int_list_cons_pattern(env, _pattern, _subject, _index, counter, setup, cleanup) do
    {env, setup, cleanup, counter}
  end

  defp bind_int_list_head_pattern(env, %{kind: :var, name: name}, subject, index)
       when name not in ["", "_"] do
    nth = "elmc_list_nth_int_default(#{subject}, #{index}, 0)"

    env
    |> EnvBindings.put_native_int_binding(name, nth)
    |> EnvBindings.put_var_type(name, "Int")
    |> EnvBindings.put_boxed_int_binding(name, false)
  end

  defp bind_int_list_head_pattern(env, _head, _subject, _index), do: env

  defp int_list_suffix_hoist_stmt(var, index, subject, env) do
    call_args = "#{index}, #{subject}"
    RcRuntimeEmit.assign_call(env, var, "elmc_list_drop_int", call_args)
  end

  defp int_list_cons_condition(subject, head_pat, tail_pat, index, env) do
    parts =
      [
        int_list_nonempty_at(subject, index),
        int_list_head_pattern_check(subject, head_pat, index, env),
        int_list_tail_suffix_check(subject, tail_pat, index + 1, env)
      ]
      |> Enum.reject(&(&1 == "1"))

    case parts do
      [] -> "1"
      _ -> Enum.join(parts, " && ")
    end
  end

  defp int_list_nonempty_at(subject, 0) do
    "#{subject} && #{subject}->tag == ELMC_TAG_INT_LIST && !elmc_int_list_is_empty(#{subject})"
  end

  defp int_list_nonempty_at(subject, index) do
    "(#{int_list_length_expr(subject)} > #{index})"
  end

  defp int_list_length_expr(subject) do
    "((#{subject})->tag == ELMC_TAG_INT_LIST && (#{subject})->payload ? ((ElmcIntListPayload *)(#{subject})->payload)->length : 0)"
  end

  defp int_list_head_pattern_check(_subject, %{kind: :var}, _index, _env), do: "1"
  defp int_list_head_pattern_check(_subject, %{kind: :wildcard}, _index, _env), do: "1"

  defp int_list_head_pattern_check(subject, %{kind: :int, value: value}, index, _env)
       when is_integer(value) do
    "((#{int_list_length_expr(subject)}) > #{index}) && elmc_list_nth_int_default(#{subject}, #{index}, #{value}) == #{value}"
  end

  defp int_list_head_pattern_check(subject, %{kind: :char, value: value}, index, _env)
       when is_integer(value) do
    "((#{int_list_length_expr(subject)}) > #{index}) && elmc_list_nth_int_default(#{subject}, #{index}, #{value}) == #{value}"
  end

  defp int_list_head_pattern_check(_subject, _pattern, _index, _env), do: "1"

  defp int_list_tail_suffix_check(subject, %{kind: :constructor, name: "[]"}, index, _env) do
    "#{int_list_length_expr(subject)} == #{index}"
  end

  defp int_list_tail_suffix_check(
         subject,
         %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}},
         index,
         env
       ) do
    int_list_cons_condition(subject, head, tail, index, env)
  end

  defp int_list_tail_suffix_check(_subject, %{kind: :var}, _index, _env), do: "1"
  defp int_list_tail_suffix_check(_subject, %{kind: :wildcard}, _index, _env), do: "1"
  defp int_list_tail_suffix_check(_subject, _pattern, _index, _env), do: "1"

  defp int_spine_cons_condition(subject, head_pat, tail_pat, env) do
    parts =
      [
        int_spine_nonempty(subject),
        int_spine_head_pattern_check(subject, head_pat, env),
        int_spine_tail_pattern_check(subject, tail_pat, env)
      ]
      |> Enum.reject(&(&1 == "1"))

    case parts do
      [] -> "1"
      _ -> Enum.join(parts, " && ")
    end
  end

  defp int_spine_nonempty(subject) do
    "#{subject} && #{subject}->tag == ELMC_TAG_INT_SPINE && !elmc_int_spine_is_empty(#{subject})"
  end

  defp int_spine_payload_head(subject) do
    "((ElmcIntSpine *)(#{subject})->payload)->head"
  end

  defp int_spine_payload_tail(subject) do
    "((ElmcIntSpine *)(#{subject})->payload)->tail"
  end

  defp int_spine_head_pattern_check(_subject, %{kind: :var}, _env), do: "1"
  defp int_spine_head_pattern_check(_subject, %{kind: :wildcard}, _env), do: "1"

  defp int_spine_head_pattern_check(subject, %{kind: :int, value: value}, _env)
       when is_integer(value) do
    "(#{int_spine_payload_head(subject)} == #{value})"
  end

  defp int_spine_head_pattern_check(subject, %{kind: :char, value: value}, _env)
       when is_integer(value) do
    "(#{int_spine_payload_head(subject)} == #{value})"
  end

  defp int_spine_head_pattern_check(subject, head_pat, env) do
    head_ref = "elmc_small_int(#{int_spine_payload_head(subject)})"
    "(#{pattern_condition(head_ref, head_pat, env)})"
  end

  defp int_spine_tail_pattern_check(subject, %{kind: :constructor, name: "[]"}, _env) do
    tail = int_spine_payload_tail(subject)
    "(#{tail} == NULL || elmc_int_spine_is_empty(#{tail}))"
  end

  defp int_spine_tail_pattern_check(
         subject,
         %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}},
         env
       ) do
    int_spine_cons_condition(int_spine_payload_tail(subject), head, tail, env)
  end

  defp int_spine_tail_pattern_check(_subject, %{kind: :var}, _env), do: "1"
  defp int_spine_tail_pattern_check(_subject, %{kind: :wildcard}, _env), do: "1"
  defp int_spine_tail_pattern_check(_subject, _pattern, _env), do: "1"

  defp float_list_cons_condition(subject, head_pat, tail_pat, index, env) do
    parts =
      [
        float_list_nonempty_at(subject, index),
        float_list_head_pattern_check(subject, head_pat, index, env),
        float_list_tail_suffix_check(subject, tail_pat, index + 1, env)
      ]
      |> Enum.reject(&(&1 == "1"))

    case parts do
      [] -> "1"
      _ -> Enum.join(parts, " && ")
    end
  end

  defp float_list_nonempty_at(subject, 0) do
    "#{subject} && #{subject}->tag == ELMC_TAG_FLOAT_LIST && !elmc_float_list_is_empty(#{subject})"
  end

  defp float_list_nonempty_at(subject, index) do
    "(#{float_list_length_expr(subject)} > #{index})"
  end

  defp float_list_length_expr(subject) do
    "((#{subject})->tag == ELMC_TAG_FLOAT_LIST && (#{subject})->payload ? ((ElmcFloatListPayload *)(#{subject})->payload)->length : 0)"
  end

  defp float_list_head_pattern_check(_subject, %{kind: :var}, _index, _env), do: "1"
  defp float_list_head_pattern_check(_subject, %{kind: :wildcard}, _index, _env), do: "1"

  defp float_list_head_pattern_check(subject, %{kind: :int, value: value}, index, _env)
       when is_integer(value) do
    "((#{float_list_length_expr(subject)}) > #{index}) && ((ElmcFloatListPayload *)(#{subject})->payload)->values[#{index}] == #{:erlang.float(value)}"
  end

  defp float_list_head_pattern_check(_subject, _pattern, _index, _env), do: "1"

  defp float_list_tail_suffix_check(subject, %{kind: :constructor, name: "[]"}, index, _env) do
    "#{float_list_length_expr(subject)} == #{index}"
  end

  defp float_list_tail_suffix_check(
         subject,
         %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}},
         index,
         env
       ) do
    float_list_cons_condition(subject, head, tail, index, env)
  end

  defp float_list_tail_suffix_check(_subject, %{kind: :var}, _index, _env), do: "1"
  defp float_list_tail_suffix_check(_subject, %{kind: :wildcard}, _index, _env), do: "1"
  defp float_list_tail_suffix_check(_subject, _pattern, _index, _env), do: "1"

  defp record_seq_cons_condition(subject, head_pat, tail_pat, index, env) do
    parts =
      [
        record_seq_nonempty_at(subject, index),
        record_seq_head_pattern_check(subject, head_pat, index, env),
        record_seq_tail_suffix_check(subject, tail_pat, index + 1, env)
      ]
      |> Enum.reject(&(&1 == "1"))

    case parts do
      [] -> "1"
      _ -> Enum.join(parts, " && ")
    end
  end

  defp record_seq_nonempty_at(subject, 0) do
    "#{subject} && #{subject}->tag == ELMC_TAG_RECORD_SEQ && !elmc_record_seq_is_empty(#{subject})"
  end

  defp record_seq_nonempty_at(subject, index) do
    "(#{record_seq_length_expr(subject)} > #{index})"
  end

  defp record_seq_length_expr(subject) do
    "((#{subject})->tag == ELMC_TAG_RECORD_SEQ && (#{subject})->payload ? ((ElmcRecordSeqPayload *)(#{subject})->payload)->length : 0)"
  end

  defp record_seq_head_pattern_check(_subject, %{kind: :var}, _index, _env), do: "1"
  defp record_seq_head_pattern_check(_subject, %{kind: :wildcard}, _index, _env), do: "1"

  defp record_seq_head_pattern_check(subject, head_pat, index, env) do
    head_ref = "elmc_record_seq_get(#{subject}, #{index})"

    "((#{record_seq_length_expr(subject)}) > #{index}) && (#{pattern_condition(head_ref, head_pat, env)})"
  end

  defp record_seq_tail_suffix_check(subject, %{kind: :constructor, name: "[]"}, index, _env) do
    "#{record_seq_length_expr(subject)} == #{index}"
  end

  defp record_seq_tail_suffix_check(
         subject,
         %{kind: :constructor, name: "::", arg_pattern: %{kind: :tuple, elements: [head, tail]}},
         index,
         env
       ) do
    record_seq_cons_condition(subject, head, tail, index, env)
  end

  defp record_seq_tail_suffix_check(_subject, %{kind: :var}, _index, _env), do: "1"
  defp record_seq_tail_suffix_check(_subject, %{kind: :wildcard}, _index, _env), do: "1"
  defp record_seq_tail_suffix_check(_subject, _pattern, _index, _env), do: "1"

  @doc false
  @spec list_case_suffix_var?(String.t()) :: boolean()
  def list_case_suffix_var?(var) when is_binary(var), do: Regex.match?(@list_case_suffix_var, var)
  def list_case_suffix_var?(_), do: false
end
