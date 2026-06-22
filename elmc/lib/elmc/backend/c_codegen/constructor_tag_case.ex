defmodule Elmc.Backend.CCodegen.ConstructorTagCase do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.IntLiteralRef
  alias Elmc.Backend.CCodegen.OwnershipTransfer
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.ValueSlots
  alias Elmc.Backend.CCodegen.PebbleMsgTag
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
  alias Elmc.Backend.CCodegen.Native.IntCase, as: NativeIntCase
  alias Elmc.Backend.CCodegen.Patterns
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.UnionMacros
  @constructor_tag_switch_min_branches 4

  @constructor_tag_switch_excluded_names MapSet.new([
                                           "Ok",
                                           "Err",
                                           "Just",
                                           "Nothing",
                                           "::",
                                           "[]"
                                         ])

  @spec branches?(Types.case_branches()) :: boolean()
  def branches?(branches) when is_list(branches) do
    tagged? =
      Enum.any?(branches, fn branch ->
        match?(%{pattern: %{kind: :constructor, tag: tag}} when is_integer(tag), branch)
      end)

    tagged? and
      Enum.all?(branches, fn branch ->
        case branch.pattern do
          %{kind: :wildcard} ->
            true

          %{kind: :constructor, tag: tag} = pattern when is_integer(tag) ->
            switchable_pattern?(pattern)

          _ ->
            false
        end
      end)
  end

  def branches?(_branches), do: false

  @spec switch_eligible?(Types.case_branches()) :: boolean()
  def switch_eligible?(branches) do
    branches?(branches) and switch_branch_count(branches) >= @constructor_tag_switch_min_branches
  end

  @spec native_subject_switch?(Types.ir_expr(), Types.case_branches(), Types.compile_env()) ::
          boolean()
  def native_subject_switch?(subject_expr, branches, env) do
    NativeIntCase.subject_expr?(subject_expr, env) and
      Enum.all?(branches, fn branch ->
        case branch.pattern do
          %{kind: :constructor} = pattern -> simple_constructor_pattern?(pattern)
          %{kind: :wildcard} -> true
          _ -> false
        end
      end)
  end

  @spec compile_native_subject(
          Types.ir_expr(),
          Types.case_branches(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  def compile_native_subject(subject_expr, branches, env, counter) do
    {subject_code, subject_ref, counter} = NativeInt.compile_expr(subject_expr, env, counter)
    next = counter + 1
    out = "tmp_#{next}"

    has_default? =
      Enum.any?(branches, fn branch -> match?(%{kind: :wildcard}, branch.pattern) end)

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next}, fn branch, {acc, c} ->
        branch_env =
          env
          |> RecordCompile.fresh_subexpr_cache()
          |> Map.put(:__into_out__, out)
          |> Map.put(:__rc_catch__, false)

        {expr_code, assignment_code, c2} =
          Host.compile_case_branch_assignment(branch.expr, out, branch_env, c)

        snippet =
          switch_branch_snippet(case_label(branch.pattern, env), expr_code, assignment_code, out)

        {acc <> snippet <> "\n", c2}
      end)

    default_case =
      if has_default? do
        ""
      else
        """
        default:
          #{out} = elmc_int_zero();
          break;
        """
        |> CSource.indent(2)
      end

    switch_body = CSource.indent(branch_code <> default_case, 2)

    code = """
    #{subject_code}
      ElmcValue *#{out} = NULL;
      switch (#{subject_ref}) {
    #{switch_body}
      }
    """

    {code, out, final_counter}
  end

  @spec compile(
          Types.case_subject(),
          Types.case_branches(),
          Types.compile_env(),
          Types.compile_counter()
        ) ::
          Types.compile_result()
  def compile(subject, branches, env, counter) do
    compile_boxed_subject(subject, branches, env, counter)
  end

  @spec compile_boxed_subject(
          Types.case_subject(),
          Types.case_branches(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  def compile_boxed_subject(subject, branches, env, counter) do
    cond do
      deferred_string_box_eligible?(branches) ->
        compile_deferred_string_box_subject(subject, branches, env, counter)

      deferred_int_box_eligible?(branches, env) ->
        compile_deferred_int_box_subject(subject, branches, env, counter)

      true ->
        compile_boxed_subject_switch(subject, branches, env, counter)
    end
  end

  defp compile_boxed_subject_switch(subject, branches, env, counter) do
    {subject_setup, subject_ref, counter} = compile_subject_ref(subject, env, counter)
    tag_ref = "case_msg_tag_#{counter + 1}"
    next = counter + 1
    out = "tmp_#{next}"

    has_default? =
      Enum.any?(branches, fn branch -> match?(%{kind: :wildcard}, branch.pattern) end)

    exhaustive? = deferred_box_exhaustive?(branches)

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next}, fn branch, {acc, c} ->
        branch_env =
          env
          |> Patterns.bind_pattern(branch.pattern, subject_ref)
          |> RecordCompile.fresh_subexpr_cache()
          |> Map.put(:__into_out__, out)
          |> Map.put(:__rc_catch__, false)

        {expr_code, assignment_code, c2} =
          Host.compile_case_branch_assignment(branch.expr, out, branch_env, c)

        snippet =
          switch_branch_snippet(case_label(branch.pattern, env), expr_code, assignment_code, out)

        {acc <> snippet <> "\n", c2}
      end)

    default_case =
      if has_default? or exhaustive? do
        ""
      else
        """
        default:
          #{out} = elmc_int_zero();
          break;
        """
        |> CSource.indent(2)
      end

    switch_body = CSource.indent(branch_code <> default_case, 2)

    code = """
    #{subject_setup}
      const int #{tag_ref} = #{message_tag_expr(subject_ref)};
      ElmcValue *#{out} = NULL;
      switch (#{tag_ref}) {
    #{switch_body}
      }
    """

    {code, out, final_counter}
  end

  defp compile_deferred_int_box_subject(subject, branches, env, counter) do
    {subject_setup, subject_ref, counter} = compile_subject_ref(subject, env, counter)
    tag_ref = "case_msg_tag_#{counter + 1}"
    next = counter + 1
    out = "tmp_#{next + 1}"
    int_scratch = "case_int_#{next + 1}"
    exhaustive? = deferred_box_exhaustive?(branches)

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next + 1}, fn branch, {acc, c} ->
        spec = branch_int_box_spec(branch, env)

        snippet =
          case spec do
            {:slot, ref} ->
              deferred_int_box_slot_snippet(case_label(branch.pattern, env), ref, int_scratch)

            :zero ->
              deferred_int_box_zero_snippet(case_label(branch.pattern, env), out)
          end

        {acc <> snippet <> "\n", c}
      end)

    default_case = deferred_box_switch_default(branches, out, exhaustive?)
    post_box = deferred_int_box_post_box(env, out, int_scratch, exhaustive?)

    switch_body = CSource.indent(branch_code <> default_case, 2)

    int_init = if exhaustive?, do: "0", else: "-1"

    code = """
    #{subject_setup}
      const int #{tag_ref} = #{message_tag_expr(subject_ref)};
      ElmcValue *#{out} = NULL;
      elmc_int_t #{int_scratch} = #{int_init};
      switch (#{tag_ref}) {
    #{switch_body}
      }
    #{post_box}
    """

    {code, out, final_counter}
  end

  defp compile_deferred_string_box_subject(subject, branches, env, counter) do
    {subject_setup, subject_ref, counter} = compile_subject_ref(subject, env, counter)
    tag_ref = "case_msg_tag_#{counter + 1}"
    next = counter + 1
    out = "tmp_#{next + 1}"
    str_scratch = "case_str_#{next + 1}"
    exhaustive? = deferred_box_exhaustive?(branches)

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next + 1}, fn branch, {acc, _c} ->
        spec = branch_string_box_spec(branch)

        snippet =
          case spec do
            {:string, literal} ->
              deferred_string_box_slot_snippet(
                case_label(branch.pattern, env),
                literal,
                str_scratch
              )

            :zero ->
              deferred_int_box_zero_snippet(case_label(branch.pattern, env), out)
          end

        {acc <> snippet <> "\n", next + 1}
      end)

    default_case = deferred_box_switch_default(branches, out, exhaustive?)
    post_box = deferred_string_box_post_box(env, out, str_scratch, exhaustive?)

    switch_body = CSource.indent(branch_code <> default_case, 2)

    code = """
    #{subject_setup}
      const int #{tag_ref} = #{message_tag_expr(subject_ref)};
      ElmcValue *#{out} = NULL;
      const char *#{str_scratch} = NULL;
      switch (#{tag_ref}) {
    #{switch_body}
      }
    #{post_box}
    """

    {code, out, final_counter}
  end

  defp deferred_box_exhaustive?(branches) when is_list(branches) do
    not Enum.any?(branches, fn %{pattern: pattern} ->
      match?(%{kind: :wildcard}, pattern)
    end)
  end

  defp deferred_box_switch_default(branches, out, exhaustive?) do
    cond do
      exhaustive? ->
        ""

      Enum.any?(branches, fn branch -> match?(%{kind: :wildcard}, branch.pattern) end) ->
        ""

      true ->
        deferred_int_box_zero_snippet("default", out)
    end
  end

  defp deferred_int_box_post_box(env, out, int_scratch, true) do
    RcRuntimeEmit.assign_into(env, out, "elmc_new_int", int_scratch)
    |> CSource.indent(2)
  end

  defp deferred_int_box_post_box(env, out, int_scratch, false) do
    """
    if (#{int_scratch} >= 0) {
      #{RcRuntimeEmit.assign_into(env, out, "elmc_new_int", int_scratch)}
    }
    """
    |> String.trim()
    |> CSource.indent(2)
  end

  defp deferred_string_box_post_box(env, out, str_scratch, true) do
    RcRuntimeEmit.assign_into(env, out, "elmc_new_string", str_scratch)
    |> CSource.indent(2)
  end

  defp deferred_string_box_post_box(env, out, str_scratch, false) do
    """
    if (#{str_scratch}) {
      #{RcRuntimeEmit.assign_into(env, out, "elmc_new_string", str_scratch)}
    }
    """
    |> String.trim()
    |> CSource.indent(2)
  end

  defp deferred_string_box_slot_snippet(label, literal, str_scratch) do
    """
    #{label}: {
      #{str_scratch} = #{literal};
      break;
    }
    """
    |> String.trim_trailing()
    |> CSource.indent(2)
  end

  defp deferred_string_box_eligible?(branches) when is_list(branches) do
    specs = Enum.map(branches, &branch_string_box_spec/1)
    string_count = Enum.count(specs, &match?({:string, _}, &1))

    string_count >= 2 and Enum.all?(specs, fn
      {:string, _} -> true
      :zero -> true
      _ -> false
    end)
  end

  defp deferred_string_box_eligible?(_branches), do: false

  defp branch_string_box_spec(%{expr: expr}), do: string_box_expr_spec(expr)

  defp string_box_expr_spec(%{op: :int_literal, value: 0}), do: :zero

  defp string_box_expr_spec(%{op: :string_literal, value: value}) when is_binary(value) do
    if String.contains?(value, <<0>>) do
      :complex
    else
      {:string, "\"#{Util.escape_c_string(value)}\""}
    end
  end

  defp string_box_expr_spec(_expr), do: :complex

  defp deferred_int_box_slot_snippet(label, ref, int_scratch) do
    """
    #{label}: {
      #{int_scratch} = #{ref};
      break;
    }
    """
    |> String.trim_trailing()
    |> CSource.indent(2)
  end

  defp deferred_int_box_zero_snippet(label, out) do
    """
    #{label}:
      #{out} = elmc_int_zero();
      break;
    """
    |> CSource.indent(2)
  end

  defp deferred_int_box_eligible?(branches, env) when is_list(branches) do
    specs = Enum.map(branches, &branch_int_box_spec(&1, env))
    slot_count = Enum.count(specs, &match?({:slot, _}, &1))

    slot_count >= 2 and Enum.all?(specs, fn
      {:slot, _} -> true
      :zero -> true
      _ -> false
    end)
  end

  defp deferred_int_box_eligible?(_branches, _env), do: false

  defp branch_int_box_spec(%{expr: expr}, env), do: int_box_expr_spec(expr, env)

  defp int_box_expr_spec(%{op: :int_literal, value: 0}, _env), do: :zero

  defp int_box_expr_spec(%{op: :int_literal, value: value} = expr, env)
       when is_integer(value) and value != 0 do
    {:slot, IntLiteralRef.ref(expr, env)}
  end

  defp int_box_expr_spec(_expr, _env), do: :complex

  @spec switch_branch_count(Types.case_branches()) :: non_neg_integer()
  defp switch_branch_count(branches) do
    branches
    |> Enum.reject(fn branch -> match?(%{pattern: %{kind: :wildcard}}, branch) end)
    |> length()
  end

  @spec switchable_pattern?(Types.pattern()) :: boolean()
  defp switchable_pattern?(%{kind: :constructor, name: name, tag: _tag} = pattern) do
    name_allowed? =
      is_nil(name) or not MapSet.member?(@constructor_tag_switch_excluded_names, name)

    name_allowed? and simple_constructor_pattern?(pattern)
  end

  @spec simple_constructor_pattern?(Types.pattern()) :: boolean()
  defp simple_constructor_pattern?(%{kind: :constructor, tag: _tag, arg_pattern: nil}), do: true

  defp simple_constructor_pattern?(%{
         kind: :constructor,
         tag: _tag,
         arg_pattern: %{kind: :wildcard}
       }),
       do: true

  defp simple_constructor_pattern?(%{kind: :constructor, tag: _tag, arg_pattern: %{kind: :var}}),
    do: true

  defp simple_constructor_pattern?(_pattern), do: false

  @doc false
  @spec compile_subject_ref(Types.case_subject(), Types.compile_env(), Types.compile_counter()) ::
          {String.t(), Types.subject_ref(), Types.compile_counter()}
  def compile_subject_ref(subject, env, counter) when is_binary(subject) do
    case Map.get(env, subject) do
      ref when is_binary(ref) ->
        {"", ref, counter}

      _ ->
        Host.compile_expr(%{op: :var, name: subject}, env, counter)
    end
  end

  def compile_subject_ref(%{op: :var, name: name}, env, counter) when is_binary(name) do
    compile_subject_ref(name, env, counter)
  end

  def compile_subject_ref(subject_expr, env, counter) do
    Host.compile_expr(subject_expr, env, counter)
  end

  defp switch_branch_snippet(label, expr_code, assignment_code, out) do
    cleanup = switch_branch_cleanup(expr_code, assignment_code, out)

    body =
      [expr_code, assignment_code, cleanup, "break;"]
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.join("\n")

    """
    #{label}: {
    #{CSource.indent(body, 2)}
    }
    """
    |> String.trim_trailing()
    |> CSource.indent(2)
  end

  @foldl_borrowed_var ~r/^list_foldl_(cursor|head|node)_\d+$/

  defp switch_branch_cleanup(expr_code, assignment_code, out) do
    body =
      [expr_code, assignment_code]
      |> Enum.filter(&is_binary/1)
      |> Enum.join("\n")

    block_scoped = block_scoped_assignments(body)

    assigned =
      Regex.scan(~r/ElmcValue \*([A-Za-z_][A-Za-z0-9_]*)\s*=/, body)
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.uniq()

    released =
      Regex.scan(~r/elmc_release\(([A-Za-z_][A-Za-z0-9_]*)\)/, body)
      |> Enum.map(fn [_, name] -> name end)
      |> MapSet.new()

    cow_drop_skip = OwnershipTransfer.cow_drop_chain_sources_to_skip(body, out)

    assigned
    |> Enum.reject(fn name ->
      name == out or
        String.starts_with?(name, "__") or
        Regex.match?(@foldl_borrowed_var, name) or
        MapSet.member?(released, name) or
        MapSet.member?(cow_drop_skip, name) or
        MapSet.member?(block_scoped, name) or
        ValueSlots.transferred?(name, body) or
        OwnershipTransfer.transferred_in_c_source?(name, body)
    end)
    |> Enum.map_join("\n", fn name ->
      ValueSlots.release(name)
      "elmc_release(#{name});"
    end)
  end

  defp block_scoped_assignments(body) when is_binary(body) do
    body
    |> String.split("\n")
    |> Enum.reduce({0, MapSet.new()}, fn line, {brace_depth, scoped} ->
      open_braces = line |> String.graphemes() |> Enum.count(&(&1 == "{"))
      close_braces = line |> String.graphemes() |> Enum.count(&(&1 == "}"))

      scoped =
        case Regex.run(~r/^\s+ElmcValue \*([A-Za-z_][A-Za-z0-9_]*)\s*=/, line) do
          [_, var] when brace_depth > 0 -> MapSet.put(scoped, var)
          _ -> scoped
        end

      brace_depth = max(brace_depth + open_braces - close_braces, 0)
      {brace_depth, scoped}
    end)
    |> elem(1)
  end

  @spec case_label(Types.pattern(), Types.compile_env()) :: String.t()
  defp case_label(%{kind: :wildcard}, _env), do: "default"

  defp case_label(%{kind: :constructor, tag: tag} = pattern, env) when is_integer(tag) do
    pebble_tag = PebbleMsgTag.tag_expr(pattern)

    ref =
      if pebble_tag == Integer.to_string(tag) do
        pattern
        |> constructor_literal_expr()
        |> UnionMacros.literal_ref(env)
      end

    "case #{ref || pebble_tag}"
  end

  defp constructor_literal_expr(%{tag: tag} = pattern) do
    %{
      op: :int_literal,
      value: tag,
      union_ctor: Map.get(pattern, :resolved_name) || Map.get(pattern, :name)
    }
  end

  @spec message_tag_expr(Types.subject_ref()) :: String.t()
  defp message_tag_expr(subject_ref) do
    "(#{subject_ref} && (#{subject_ref})->tag == ELMC_TAG_INT ? elmc_as_int(#{subject_ref}) : " <>
      "(#{subject_ref} && (#{subject_ref})->tag == ELMC_TAG_TUPLE2 && (#{subject_ref})->payload != NULL ? " <>
      "elmc_as_int(((ElmcTuple2 *)(#{subject_ref})->payload)->first) : -1))"
  end
end
