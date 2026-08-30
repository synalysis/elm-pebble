defmodule Elmc.Backend.Plan.Lower.PatternMatch do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types


  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Builder

  @spec match_condition(Types.pattern(), non_neg_integer(), Builder.t()) ::
          Types.match_condition_result()
  def match_condition(pattern, subject_reg, b)
      when is_map(pattern) and is_integer(subject_reg) do
    do_match_condition(pattern, subject_reg, b)
  end

  def match_condition(_, _, _), do: :unsupported

  @spec do_match_condition(Types.pattern() | map(), Types.reg(), Builder.t()) ::
          Types.match_condition_result()

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

  # Record patterns only bind fields (`{ data }`); they never discriminate.
  # PatternBind peels fields; match must accept so constructor payloads like
  # `Texture { data }` (Scene3d materials) can lower through GuardedSwitch.
  defp do_match_condition(%{kind: :record, fields: fields}, _subject_reg, b)
       when is_list(fields) do
    const_true(b)
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

  defp do_match_condition(%{kind: :constructor} = pattern, subject_reg, b) do
    name = Map.get(pattern, :name)
    resolved = Map.get(pattern, :resolved_name) || name

    cond do
      cons_pattern?(pattern) ->
        # `::` is not a tagged union — only nonempty is not enough. Recurse into
        # head/tail so `[ "wasm" ]` / `"a" :: "b" :: []` actually test literals
        # (Route.segmentsToRoute). Skipping that made every nonempty list match
        # the first cons arm (Articles), so deep links always mismatched.
        match_cons_pattern(pattern, subject_reg, b)

      maybe_nothing?(resolved, name) ->
        test_maybe_nothing(subject_reg, b)

      maybe_just?(resolved, name) ->
        test_maybe_just(subject_reg, b)

      short_ctor(resolved || name) == "[]" ->
        test_list_empty(subject_reg, b)

      bool_ctor?(resolved || name) ->
        test_bool_ctor(resolved || name, subject_reg, b)

      unit_ctor?(resolved || name) ->
        # `()` is a singleton with no tag/payload (elmc_unit()); it always
        # matches. Needed as a *nested* arg pattern (`Ok ()`, `Just ()`), where
        # test_ctor_tag would otherwise fail to resolve a nonexistent tag.
        const_true(b)

      true ->
        match_ctor_with_arg_pattern(pattern, subject_reg, b)
    end
  end

  defp do_match_condition(_, _, _), do: :unsupported

  @spec match_cons_pattern(Types.pattern(), Types.reg(), Builder.t()) ::
          Types.match_condition_result()

  defp match_cons_pattern(pattern, subject_reg, b) do
    case cons_head_tail(pattern) do
      {:ok, head_pat, tail_pat} ->
        with {:ok, nonempty_cond, b1} <- test_list_nonempty(subject_reg, b),
             {:ok, head_reg, b2} <- peel_list_head(subject_reg, b1),
             {:ok, tail_reg, b3} <- peel_list_tail(subject_reg, b2),
             {:ok, head_cond, b4} <- do_match_condition(head_pat, head_reg, b3),
             {:ok, tail_cond, b5} <- do_match_condition(tail_pat, tail_reg, b4),
             {:ok, elems_cond, b6} <- bool_and(head_cond, tail_cond, b5) do
          bool_and(nonempty_cond, elems_cond, b6)
        else
          _ -> :unsupported
        end

      :error ->
        test_list_nonempty(subject_reg, b)
    end
  end

  @spec cons_head_tail(map() | term()) :: {:ok, Types.pattern(), Types.pattern()} | :error

  defp cons_head_tail(%{arg_pattern: %{kind: :tuple, elements: [head, tail]}}),
    do: {:ok, head, tail}

  defp cons_head_tail(_), do: :error

  @spec peel_list_head(Types.reg(), Builder.t()) :: Types.compile_reg_result()

  defp peel_list_head(subject_reg, b) do
    with {:ok, maybe_reg, b1} <- emit_owned_list_op(:list_head, subject_reg, b),
         {:ok, head_reg, b2} <- emit_maybe_just_payload_retain(maybe_reg, b1) do
      {:ok, head_reg, b2}
    end
  end

  @spec peel_list_tail(Types.reg(), Builder.t()) :: Types.compile_reg_result()

  defp peel_list_tail(subject_reg, b) do
    with {:ok, maybe_reg, b1} <- emit_owned_list_op(:list_tail, subject_reg, b),
         {:ok, tail_reg, b2} <- emit_maybe_just_payload_retain(maybe_reg, b1) do
      {:ok, tail_reg, b2}
    end
  end

  # `elmc_list_head` / `elmc_list_tail` return an owned Maybe. Peeling the Just
  # payload must retain it before the Maybe is released — otherwise match
  # conditions like `'n' :: 'u' :: rest` use a dangling payload (heap corruption).
  @spec emit_maybe_just_payload_retain(Types.reg(), Builder.t()) :: Types.compile_reg_result()

  defp emit_maybe_just_payload_retain(maybe_reg, b) when is_integer(maybe_reg) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :call_runtime, %{
        dest: dest,
        args: %{
          builtin: :retain,
          args: [maybe_reg],
          view_peel: :maybe_just_payload,
          view_peel_args: [maybe_reg]
        },
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [maybe_reg],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  @spec emit_owned_list_op(:list_head | :list_tail, Types.reg(), Builder.t()) ::
          Types.compile_reg_result()

  defp emit_owned_list_op(builtin, arg_reg, b)
       when builtin in [:list_head, :list_tail] and is_integer(arg_reg) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :call_runtime, %{
        dest: dest,
        args: %{builtin: builtin, args: [arg_reg]},
        effects: Types.fallible_effects(dest, [arg_reg], [])
      })

    {:ok, dest, b2}
  end

  @spec match_ctor_with_arg_pattern(Types.pattern() | map(), Types.reg(), Builder.t()) ::
          Types.match_condition_result()

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

  @spec emit_union_payload_view(Types.reg(), Builder.t()) :: Types.compile_reg_result()

  defp emit_union_payload_view(subject_reg, b) do
    # Must retain into an owned slot. The C helper `elmc_union_payload` returns a
    # borrow; assigning that borrow to owned[] and later releasing it frees the
    # subject's nested payload while the subject still points at it (UAF).
    # Match `Expr.compile_borrow_view_builtin(:union_payload, …)` → tuple_proj.
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :tuple_proj, %{
        dest: dest,
        args: %{base: subject_reg, which: :second},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [subject_reg],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  @spec emit_char_code(Types.reg(), Builder.t()) :: Types.compile_reg_result()

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

  @spec const_true(Builder.t()) :: Types.compile_reg_result()

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

  @spec const_int(integer(), Builder.t()) :: Types.compile_reg_result()

  defp const_int(value, b) do
    {reg, b1} = Builder.emit_const_int(b, value)
    {:ok, reg, b1}
  end

  @spec bool_and(Types.reg(), Types.reg(), Builder.t()) :: Types.compile_reg_result()

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

  @spec compare_eq(Types.reg(), Types.reg(), Builder.t()) :: Types.compile_reg_result()

  defp compare_eq(left, right, b) do
    {dest, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :compare, %{
        dest: dest,
        # Official Int / Char-code patterns compare values, not heap handles.
        # WASM `:pointer` (the emit default) is `i32.eq` of a tuple_proj box
        # against `const_int 1` — handle 1 is UNIT, so `(1, 2, 3)` never matches.
        args: %{kind: :eq, left: left, right: right, mode: :int_boxed},
        effects: %{
          produces: {:owned, dest},
          consumes: [],
          borrows: [left, right],
          fallible: false
        }
      })

    {:ok, dest, b2}
  end

  @spec tuple_proj(Types.reg(), :first | :second, Builder.t()) :: Types.compile_reg_result()

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

  @spec test_string_literal(Types.reg(), String.t(), Builder.t()) :: Types.compile_reg_result()

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

  @spec test_maybe_nothing(Types.reg(), Builder.t()) :: Types.compile_reg_result()

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

  @spec test_maybe_just(Types.reg(), Builder.t()) :: Types.compile_reg_result()

  defp test_maybe_just(subject_reg, b) do
    with {:ok, nothing_reg, b1} <- test_maybe_nothing(subject_reg, b),
         {:ok, zero, b2} <- const_int(0, b1) do
      compare_eq(nothing_reg, zero, b2)
    end
  end

  @spec test_list_empty(Types.reg(), Builder.t()) :: Types.compile_reg_result()

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

  @spec test_ctor_tag(Types.pattern(), Types.reg(), Builder.t()) ::
          Types.match_condition_result()

  defp test_ctor_tag(pattern, subject_reg, b) do
    tag = pattern_tag(pattern)
    ctor = Map.get(pattern, :resolved_name) || Map.get(pattern, :name)

    if is_integer(tag) do
      {dest, b1} = Builder.fresh_reg(b)

      args =
        if is_binary(ctor) do
          %{subject: subject_reg, tag: tag, union_ctor: ctor}
        else
          %{subject: subject_reg, tag: tag}
        end

      {_, b2} =
        Builder.emit(b1, :test_ctor_tag, %{
          dest: dest,
          args: args,
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

  @spec bool_ctor?(String.t() | term()) :: boolean()

  defp bool_ctor?(name) when is_binary(name), do: short_ctor(name) in ["True", "False"]
  defp bool_ctor?(_), do: false

  @spec unit_ctor?(String.t() | term()) :: boolean()

  defp unit_ctor?(name) when is_binary(name), do: short_ctor(name) == "()"
  defp unit_ctor?(_), do: false

  @spec test_bool_ctor(String.t(), Types.reg(), Builder.t()) :: Types.compile_reg_result()

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

  @spec maybe_nothing?(term(), term()) :: boolean()

  defp maybe_nothing?(resolved, name) do
    short_ctor(resolved || name) == "Nothing"
  end

  @spec maybe_just?(term(), term()) :: boolean()

  defp maybe_just?(resolved, name) do
    short_ctor(resolved || name) == "Just"
  end

  @spec short_ctor(String.t() | term()) :: String.t()

  defp short_ctor(name) when is_binary(name), do: name |> String.split(".") |> List.last()
  defp short_ctor(_), do: ""

  @spec pattern_tag(map() | Types.pattern()) :: integer() | nil

  defp pattern_tag(%{tag: tag} = pattern) when is_integer(tag) do
    # Re-resolve ambiguous short names even when IR baked a tag (Group poison).
    name = Map.get(pattern, :resolved_name) || Map.get(pattern, :name)

    resolved =
      if is_binary(name) do
        tags = Process.get(:elmc_constructor_tags, %{})
        Elmc.Backend.CCodegen.IRQueries.lookup_tag(tags, name)
      end

    if is_integer(resolved), do: resolved, else: tag
  end

  defp pattern_tag(pattern) do
    name = Map.get(pattern, :resolved_name) || Map.get(pattern, :name)

    if is_binary(name) do
      tags = Process.get(:elmc_constructor_tags, %{})
      Elmc.Backend.CCodegen.IRQueries.lookup_tag(tags, name)
    end
  end

  @spec nest_tuple_elements([Types.pattern()]) :: [Types.pattern()]

  defp nest_tuple_elements([left, right]), do: [left, right]

  defp nest_tuple_elements([left | rest]),
    do: [left, %{kind: :tuple, elements: nest_tuple_elements(rest)}]

  @spec cons_pattern?(map() | term()) :: boolean()

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

  @spec test_list_nonempty(Types.reg(), Builder.t()) :: Types.compile_reg_result()

  defp test_list_nonempty(subject_reg, b) do
    with {:ok, empty_reg, b1} <- test_list_empty(subject_reg, b),
         {:ok, zero, b2} <- const_int(0, b1) do
      compare_eq(empty_reg, zero, b2)
    end
  end
end
