defmodule Elmc.Backend.CCodegen.Patterns do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @spec pattern_condition(String.t(), Types.pattern()) :: String.t()
  def pattern_condition(_subject_ref, %{kind: :wildcard}), do: "1"
  def pattern_condition(_subject_ref, %{kind: :var}), do: "1"

  def pattern_condition(subject_ref, pattern)
       when is_map(pattern) and not is_binary(subject_ref) do
    pattern_condition(pattern_subject_ref(subject_ref), pattern)
  end

  def pattern_condition(subject_ref, %{kind: :int, value: value}) when is_integer(value) do
    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_INT && elmc_as_int(#{subject_ref}) == #{value}"
  end

  def pattern_condition(subject_ref, %{kind: :tuple, elements: [left, right]}) do
    left_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->first"
    right_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"

    "#{subject_ref} && #{subject_ref}->tag == ELMC_TAG_TUPLE2 && (#{pattern_condition(left_ref, left)}) && (#{pattern_condition(right_ref, right)})"
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

  def pattern_condition(subject_ref, %{kind: :constructor, tag: tag, arg_pattern: arg_pattern})
       when is_integer(tag) and is_map(arg_pattern) do
    value_ref = "((ElmcTuple2 *)#{subject_ref}->payload)->second"

    tagged_match =
      "((#{subject_ref})->tag == ELMC_TAG_TUPLE2 && (#{subject_ref})->payload != NULL && elmc_as_int(((ElmcTuple2 *)(#{subject_ref})->payload)->first) == #{tag} && (#{pattern_condition(value_ref, arg_pattern)}))"

    "(#{subject_ref}) && #{tagged_match}"
  end

  def pattern_condition(subject_ref, %{kind: :constructor, tag: tag}) when is_integer(tag) do
    int_match = "((#{subject_ref})->tag == ELMC_TAG_INT && elmc_as_int(#{subject_ref}) == #{tag})"

    tuple_match =
      "((#{subject_ref})->tag == ELMC_TAG_TUPLE2 && (#{subject_ref})->payload != NULL && elmc_as_int(((ElmcTuple2 *)(#{subject_ref})->payload)->first) == #{tag})"

    "(#{subject_ref}) && (#{int_match} || #{tuple_match})"
  end

  def pattern_condition(_subject_ref, _pattern), do: "0"

  @spec bind_pattern(Types.compile_env(), Types.pattern(), Types.subject_ref()) ::
          Types.compile_env()
  def bind_pattern(env, %{kind: :wildcard}, _subject_ref), do: env

  def bind_pattern(env, %{kind: :var, name: bind}, subject_ref) do
    Map.put(env, bind, pattern_subject_ref(subject_ref))
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

    value_ref =
      "((#{subject_ref}->tag == ELMC_TAG_MAYBE) ? ((ElmcMaybe *)#{subject_ref}->payload)->value : ((ElmcTuple2 *)#{subject_ref}->payload)->second)"

    env = if is_binary(bind), do: Map.put(env, bind, value_ref), else: env
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
    env = if is_binary(bind), do: Map.put(env, bind, subject_ref), else: env

    env
    |> bind_pattern(head, "((ElmcCons *)#{subject_ref}->payload)->head")
    |> bind_pattern(tail, "((ElmcCons *)#{subject_ref}->payload)->tail")
  end

  def bind_pattern(env, %{kind: :record, fields: fields, bind: bind}, subject_ref)
       when is_list(fields) do
    subject_ref = pattern_subject_ref(subject_ref)
    env = if is_binary(bind), do: Map.put(env, bind, subject_ref), else: env

    Enum.reduce(fields, env, fn field, acc ->
      case field do
        "value" ->
          Map.put(acc, field, "((ElmcTuple2 *)#{subject_ref}->payload)->first")

        "temperature" ->
          Map.put(acc, field, "((ElmcTuple2 *)#{subject_ref}->payload)->second")

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

  @spec pattern_subject_ref(Types.subject_ref()) :: String.t()
  defp pattern_subject_ref(subject_ref) when is_binary(subject_ref), do: subject_ref
  defp pattern_subject_ref(%{op: :var, name: name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{"op" => :var, "name" => name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{name: name}) when is_binary(name), do: name
  defp pattern_subject_ref(%{"name" => name}) when is_binary(name), do: name
  defp pattern_subject_ref(subject_ref), do: inspect(subject_ref)
end
