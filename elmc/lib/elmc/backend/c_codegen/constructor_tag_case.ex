defmodule Elmc.Backend.CCodegen.ConstructorTagCase do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.PebbleMsgTag
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
        {expr_code, assignment_code, c2} =
          Host.compile_case_branch_assignment(branch.expr, out, env, c)

        snippet = """
        #{case_label(branch.pattern, env)}:
        #{CSource.indent(expr_code, 4)}
            #{assignment_code}
            break;
        """

        {acc <> snippet, c2}
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
      end

    code = """
    #{subject_code}
      ElmcValue *#{out} = elmc_int_zero();
      switch (#{subject_ref}) {
      #{branch_code}#{default_case}
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
    {subject_setup, subject_ref, counter} = compile_subject_ref(subject, env, counter)
    tag_ref = "case_msg_tag_#{counter + 1}"
    next = counter + 1
    out = "tmp_#{next}"

    has_default? =
      Enum.any?(branches, fn branch -> match?(%{kind: :wildcard}, branch.pattern) end)

    {branch_code, final_counter} =
      Enum.reduce(branches, {"", next}, fn branch, {acc, c} ->
        branch_env = Patterns.bind_pattern(env, branch.pattern, subject_ref)

        {expr_code, assignment_code, c2} =
          Host.compile_case_branch_assignment(branch.expr, out, branch_env, c)

        snippet = """
        #{case_label(branch.pattern, env)}:
        #{CSource.indent(expr_code, 4)}
            #{assignment_code}
            break;
        """

        {acc <> snippet, c2}
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
      end

    code = """
    #{subject_setup}
      const int #{tag_ref} = #{message_tag_expr(subject_ref)};
      ElmcValue *#{out} = elmc_int_zero();
      switch (#{tag_ref}) {
      #{branch_code}#{default_case}
      }
    """

    {code, out, final_counter}
  end

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
    {"", Map.get(env, subject, subject), counter}
  end

  def compile_subject_ref(%{op: :var, name: name}, env, counter) when is_binary(name) do
    compile_subject_ref(name, env, counter)
  end

  def compile_subject_ref(subject_expr, env, counter) do
    Host.compile_expr(subject_expr, env, counter)
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
