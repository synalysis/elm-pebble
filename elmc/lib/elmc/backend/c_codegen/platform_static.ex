defmodule Elmc.Backend.CCodegen.PlatformStatic do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @type polarity :: :when_defined | :when_not_defined
  @type branch :: {String.t(), polarity()}

  @native_bool_c_type "bool"

  @display_shape_targets MapSet.new([
    "Pebble.Platform.displayShapeIsRound",
    "Platform.displayShapeIsRound"
  ])

  @color_capability_targets MapSet.new([
    "Pebble.Platform.colorCapabilityIsColor",
    "Platform.colorCapabilityIsColor"
  ])

  @spec platform_static_branch(Types.ir_expr() | term()) :: branch() | nil
  def platform_static_branch(expr) do
    expr
    |> normalize_platform_static_expr()
    |> platform_static_form()
  end

  @spec platform_static_and_if(Types.ir_expr() | term()) ::
          {:and, String.t(), polarity(), Types.ir_expr()} | nil
  def platform_static_and_if(expr) do
    expr
    |> normalize_platform_static_expr()
    |> platform_static_and_if_form()
  end

  defp platform_static_and_if_form(%{
        op: :if,
        cond: inner_cond,
        then_expr: inner_then,
        else_expr: else_expr
      }) do
    if false_else?(else_expr) do
      case platform_static_branch(inner_cond) do
        {macro, polarity} -> {:and, macro, polarity, inner_then}
        nil -> nil
      end
    end
  end

  defp platform_static_and_if_form(%{
        op: :call,
        name: op,
        args: [left, right]
      })
      when op in ["&&", "Basics.and", "and"] do
    case platform_static_branch(left) do
      {macro, polarity} -> {:and, macro, polarity, right}
      nil -> nil
    end
  end

  defp platform_static_and_if_form(%{
        op: :qualified_call,
        target: target,
        args: [left, right]
      }) do
    if Host.normalize_special_target(target) in ["Basics.and", "&&", "and"] do
      platform_static_and_if_form(%{op: :call, name: "&&", args: [left, right]})
    end
  end

  defp platform_static_and_if_form(_expr), do: nil

  defp false_else?(%{op: :bool_literal, value: false}), do: true
  defp false_else?(%{op: :int_literal, value: 0}), do: true

  defp false_else?(%{op: :constructor_call, target: target, args: []}) when is_binary(target),
    do: String.ends_with?(target, ".False") or target in ["False", "Basics.False"]

  defp false_else?(_expr), do: false

  defp normalize_platform_static_expr(%{op: :runtime_call, function: "elmc_basics_not", args: [inner]}) do
    %{op: :runtime_call, function: "elmc_basics_not", args: [normalize_platform_static_expr(inner)]}
  end

  defp normalize_platform_static_expr(%{op: :call, name: name, args: [inner]})
       when name in ["not", "Basics.not"],
       do: %{op: :call, name: name, args: [normalize_platform_static_expr(inner)]}

  defp normalize_platform_static_expr(%{op: :qualified_call, target: target, args: args}) do
    case Host.special_value_from_target(Host.normalize_special_target(target), args) do
      nil ->
        normalized_args = Enum.map(args || [], &normalize_platform_static_expr/1)
        %{op: :qualified_call, target: target, args: normalized_args}

      rewritten ->
        normalize_platform_static_expr(rewritten)
    end
  end

  defp normalize_platform_static_expr(%{op: :call, name: name, args: args}) when is_binary(name) do
    case Host.special_value_from_target(name, args) do
      nil ->
        normalized_args = Enum.map(args || [], &normalize_platform_static_expr/1)
        %{op: :call, name: name, args: normalized_args}

      rewritten ->
        normalize_platform_static_expr(rewritten)
    end
  end

  defp normalize_platform_static_expr(expr), do: expr

  @spec platform_static_macro(Types.ir_expr() | term()) :: String.t() | nil
  def platform_static_macro(expr) do
    case platform_static_branch(expr) do
      {macro, _} -> macro
      nil -> nil
    end
  end

  @spec platform_static?(Types.ir_expr() | term()) :: boolean()
  def platform_static?(expr), do: platform_static_branch(expr) != nil

  @spec ifdef_guard(String.t(), polarity()) :: String.t()
  def ifdef_guard(macro, :when_defined), do: "defined(#{macro})"
  def ifdef_guard(macro, :when_not_defined), do: "!defined(#{macro})"

  @spec invert_polarity(polarity()) :: polarity()
  def invert_polarity(:when_defined), do: :when_not_defined
  def invert_polarity(:when_not_defined), do: :when_defined

  @spec wrap_branches(String.t(), polarity(), String.t(), String.t()) :: String.t()
  def wrap_branches(macro, polarity, then_code, else_code) do
    guard = ifdef_guard(macro, polarity)

    """
    #if #{guard}
    #{then_code}#else
    #{else_code}#endif
    """
  end

  @spec merge_refs(String.t(), polarity(), String.t(), String.t(), String.t()) :: String.t()
  def merge_refs(macro, polarity, var, then_ref, else_ref) do
    guard = ifdef_guard(macro, polarity)

    """
      #if #{guard}
      const elmc_int_t #{var} = #{then_ref};
      #else
      const elmc_int_t #{var} = #{else_ref};
      #endif
    """
  end

  @spec compile_native_bool(String.t(), polarity(), Types.compile_counter(), keyword()) ::
          {String.t(), String.t(), Types.compile_counter()}
  def compile_native_bool(macro, polarity, counter, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "native_b")
    next = counter + 1
    out = "#{prefix}_#{next}"
    {true_val, false_val} = polarity_values(polarity)

    code = """
    #if defined(#{macro})
      const #{@native_bool_c_type} #{out} = #{true_val};
    #else
      const #{@native_bool_c_type} #{out} = #{false_val};
    #endif
    """

    {code, out, next}
  end

  defp platform_static_form(%{platform_static_macro: macro}) when is_binary(macro),
    do: {macro, :when_defined}

  defp platform_static_form(%{op: :qualified_call, target: target}) when is_binary(target) do
    case macro_for_target(target) do
      nil -> nil
      macro -> {macro, :when_defined}
    end
  end

  defp platform_static_form(%{op: :runtime_call, function: "elmc_basics_not", args: [inner]}),
    do: invert_branch(platform_static_form(inner))

  defp platform_static_form(%{op: :call, name: name, args: [inner]})
       when name in ["not", "Basics.not"],
       do: invert_branch(platform_static_form(inner))

  defp platform_static_form(%{op: :qualified_call, target: target, args: [inner]}) do
    if Host.normalize_special_target(target) == "Basics.not" do
      invert_branch(platform_static_form(inner))
    end
  end

  defp platform_static_form(_expr), do: nil

  defp invert_branch({macro, polarity}), do: {macro, invert_polarity(polarity)}
  defp invert_branch(nil), do: nil

  defp macro_for_target(target) do
    cond do
      MapSet.member?(@display_shape_targets, target) -> "PBL_ROUND"
      MapSet.member?(@color_capability_targets, target) -> "PBL_COLOR"
      true -> nil
    end
  end

  defp polarity_values(:when_defined), do: {"true", "false"}
  defp polarity_values(:when_not_defined), do: {"false", "true"}
end
