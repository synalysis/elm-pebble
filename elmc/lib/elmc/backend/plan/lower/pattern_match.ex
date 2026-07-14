defmodule Elmc.Backend.Plan.Lower.PatternMatch do
  @moduledoc false

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Builder

  @spec match_condition(Types.pattern(), non_neg_integer(), Builder.t()) ::
          Types.match_condition_result()
  def match_condition(pattern, subject_reg, b)
      when is_map(pattern) and is_integer(subject_reg) do
    do_match_condition(pattern, subject_reg, b)
  end

  def match_condition(_, _, _), do: :unsupported

  defp do_match_condition(%{kind: :wildcard}, _subject_reg, b),
    do: const_true(b)

  defp do_match_condition(%{kind: :var}, _subject_reg, b),
    do: const_true(b)

  defp do_match_condition(%{kind: :string, value: value}, subject_reg, b)
       when is_binary(value) do
    test_string_literal(subject_reg, value, b)
  end

  defp do_match_condition(%{kind: :char, value: value}, subject_reg, b)
       when is_integer(value) do
    with {:ok, code_reg, b1} <- emit_char_code(subject_reg, b),
         {:ok, lit_reg, b2} <- const_int(value, b1) do
      compare_eq(code_reg, lit_reg, b2)
    end
  end

  defp do_match_condition(%{kind: :int, value: value}, subject_reg, b)
       when is_integer(value) do
    with {:ok, lit_reg, b1} <- const_int(value, b) do
      compare_eq(subject_reg, lit_reg, b1)
    end
  end

  defp do_match_condition(%{kind: :tuple, elements: elements}, subject_reg, b)
       when is_list(elements) and length(elements) > 2 do
    do_match_condition(
      %{kind: :tuple, elements: nest_tuple_elements(elements)},
      subject_reg,
      b
    )
  end

  defp do_match_condition(%{kind: :tuple, elements: [left, right]}, subject_reg, b) do
    with {:ok, left_reg, b1} <- tuple_proj(subject_reg, :first, b),
         {:ok, right_reg, b2} <- tuple_proj(subject_reg, :second, b1),
         {:ok, left_cond, b3} <- do_match_condition(left, left_reg, b2),
         {:ok, right_cond, b4} <- do_match_condition(right, right_reg, b3) do
      bool_and(left_cond, right_cond, b4)
    else
      _ -> :unsupported
    end
  end

  defp do_match_condition(%{kind: :constructor, name: name} = pattern, subject_reg, b) do
    resolved = Map.get(pattern, :resolved_name) || name

    cond do
      cons_pattern?(pattern) ->
        test_list_nonempty(subject_reg, b)

      maybe_nothing?(resolved, name) ->
        test_maybe_nothing(subject_reg, b)

      maybe_just?(resolved, name) ->
        test_maybe_just(subject_reg, b)

      short_ctor(resolved || name) == "[]" ->
        test_list_empty(subject_reg, b)

      bool_ctor?(resolved || name) ->
        test_bool_ctor(resolved || name, subject_reg, b)

      true ->
        match_ctor_with_arg_pattern(pattern, subject_reg, b)
    end
  end

  defp do_match_condition(_, _, _), do: :unsupported

  defp match_ctor_with_arg_pattern(%{arg_pattern: arg_pattern} = pattern, subject_reg, b)
       when is_map(arg_pattern) do
    with {:ok, tag_cond, b1} <- test_ctor_tag(pattern, subject_reg, b),
         {:ok, payload_reg, b2} <- emit_union_payload_view(subject_reg, b1),
         {:ok, arg_cond, b3} <- do_match_condition(arg_pattern, payload_reg, b2) do
      bool_and(tag_cond, arg_cond, b3)
    else
      _ -> :unsupported
    end
  end

  defp match_ctor_with_arg_pattern(pattern, subject_reg, b),
    do: test_ctor_tag(pattern, subject_reg, b)

  defp emit_union_payload_view(subject_reg, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :call_runtime, %{
        dest: dest,
        args: %{builtin: :union_payload, args: [subject_reg]},
        effects: %{
          produces: nil,
          consumes: [],
          borrows: [subject_reg],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  defp emit_char_code(subject_reg, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :call_runtime, %{
        dest: dest,
        args: %{builtin: :char_to_code, args: [subject_reg]},
        effects: %{
          produces: nil,
          consumes: [],
          borrows: [subject_reg],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  defp const_true(b) do
    {reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :const_int, %{
        dest: reg,
        args: %{value: 1},
        effects: %{
          produces: {:owned, reg},
          consumes: [],
          borrows: [],
          fallible: false
        }
      })

    {:ok, reg, b2}
  end

  defp const_int(value, b) do
    {reg, b1} = Builder.emit_const_int(b, value)
    {:ok, reg, b1}
  end

  defp bool_and(left, right, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :bool_and, %{
        dest: dest,
        args: %{left: left, right: right},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [left, right],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  defp compare_eq(left, right, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :compare, %{
        dest: dest,
        args: %{kind: :eq, left: left, right: right},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [left, right],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  defp tuple_proj(base_reg, which, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :tuple_proj, %{
        dest: dest,
        args: %{base: base_reg, which: which},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [base_reg],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  defp test_string_literal(subject_reg, literal, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :test_string_literal, %{
        dest: dest,
        args: %{subject: subject_reg, literal: literal},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [subject_reg],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  defp test_maybe_nothing(subject_reg, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :test_maybe_nothing, %{
        dest: dest,
        args: %{reg: subject_reg},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [subject_reg],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  defp test_maybe_just(subject_reg, b) do
    with {:ok, nothing_reg, b1} <- test_maybe_nothing(subject_reg, b),
         {:ok, zero, b2} <- const_int(0, b1) do
      compare_eq(nothing_reg, zero, b2)
    end
  end

  defp test_list_empty(subject_reg, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :test_list_empty, %{
        dest: dest,
        args: %{reg: subject_reg},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [subject_reg],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  defp test_ctor_tag(pattern, subject_reg, b) do
    tag = pattern_tag(pattern)

    if is_integer(tag) do
      {dest, b1} = Builder.fresh_reg(b)

      {_, b2} =
        Builder.emit(b1, :test_ctor_tag, %{
          dest: dest,
          args: %{subject: subject_reg, tag: tag},
          effects: %{
            produces: {:owned, dest},
            consumes: [],
            borrows: [subject_reg],
            fallible: false
          }
        })

      {:ok, dest, b2}
    else
      :unsupported
    end
  end

  defp bool_ctor?(name) when is_binary(name), do: short_ctor(name) in ["True", "False"]
  defp bool_ctor?(_), do: false

  defp test_bool_ctor(name, subject_reg, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :test_bool, %{
        dest: dest,
        args: %{subject: subject_reg, want_true: short_ctor(name) == "True"},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [subject_reg],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  defp maybe_nothing?(resolved, name) do
    short_ctor(resolved || name) == "Nothing"
  end

  defp maybe_just?(resolved, name) do
    short_ctor(resolved || name) == "Just"
  end

  defp short_ctor(name) when is_binary(name), do: name |> String.split(".") |> List.last()
  defp short_ctor(_), do: ""

  defp pattern_tag(%{tag: tag}) when is_integer(tag), do: tag

  defp pattern_tag(pattern) do
    name = Map.get(pattern, :resolved_name) || Map.get(pattern, :name)

    if is_binary(name) do
      tags = Process.get(:elmc_constructor_tags, %{})

      Map.get(tags, name) ||
        Map.get(tags, short_ctor(name)) ||
        lookup_qualified_tag(name, tags)
    end
  end

  defp lookup_qualified_tag(name, tags) do
    Enum.find_value(tags, fn {key, tag} ->
      if String.ends_with?(key, "." <> short_ctor(name)), do: tag
    end)
  end

  defp nest_tuple_elements([left, right]), do: [left, right]

  defp nest_tuple_elements([left | rest]),
    do: [left, %{kind: :tuple, elements: nest_tuple_elements(rest)}]

  defp cons_pattern?(%{kind: :constructor, name: name, arg_pattern: %{kind: :tuple, elements: elements}})
       when is_list(elements) and length(elements) == 2 do
    short_ctor(name) == "::"
  end

  defp cons_pattern?(%{resolved_name: "List.::", arg_pattern: %{kind: :tuple, elements: elements}})
       when is_list(elements) and length(elements) == 2,
       do: true

  defp cons_pattern?(%{kind: :constructor, resolved_name: "List.::", arg_pattern: %{kind: :tuple, elements: elements}})
       when is_list(elements) and length(elements) == 2,
       do: true

  defp cons_pattern?(_), do: false

  defp test_list_nonempty(subject_reg, b) do
    with {:ok, empty_reg, b1} <- test_list_empty(subject_reg, b),
         {:ok, zero, b2} <- const_int(0, b1) do
      compare_eq(empty_reg, zero, b2)
    end
  end
end
