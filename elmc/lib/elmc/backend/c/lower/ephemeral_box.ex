defmodule Elmc.Backend.C.Lower.EphemeralBox do
  @moduledoc false

  alias Elmc.Backend.CCodegen.RcRuntimeEmit

  @sep <<0x1E>>

  @prefix_int "__ELMC_BOX_INT__"
  @prefix_bool "__ELMC_BOX_BOOL__"
  @prefix_tuple2 "__ELMC_BOX_TUPLE2__"
  @prefix_tuple2_ints "__ELMC_BOX_TUPLE2_INTS__"
  @prefix_string "__ELMC_BOX_STRING__"
  @prefix_string_len "__ELMC_BOX_STRING_LEN__"

  @spec int(String.t()) :: String.t()
  def int(expr) when is_binary(expr), do: @prefix_int <> @sep <> expr

  @spec bool(String.t()) :: String.t()
  def bool(expr) when is_binary(expr), do: @prefix_bool <> @sep <> expr

  @spec tuple2(String.t(), String.t()) :: String.t()
  def tuple2(left, right) when is_binary(left) and is_binary(right),
    do: @prefix_tuple2 <> @sep <> left <> @sep <> right

  @spec tuple2_ints(String.t(), String.t()) :: String.t()
  def tuple2_ints(left, right) when is_binary(left) and is_binary(right),
    do: @prefix_tuple2_ints <> @sep <> left <> @sep <> right

  @spec string(String.t()) :: String.t()
  def string(expr) when is_binary(expr), do: @prefix_string <> @sep <> expr

  @spec string_len(String.t(), String.t()) :: String.t()
  def string_len(expr, len) when is_binary(expr) and is_binary(len),
    do: @prefix_string_len <> @sep <> expr <> @sep <> len

  @spec ephemeral?(String.t()) :: boolean()
  def ephemeral?(ref) when is_binary(ref) do
    String.starts_with?(ref, @prefix_int) or
      String.starts_with?(ref, @prefix_bool) or
      String.starts_with?(ref, @prefix_tuple2_ints) or
      String.starts_with?(ref, @prefix_tuple2) or
      String.starts_with?(ref, @prefix_string_len) or
      String.starts_with?(ref, @prefix_string)
  end

  def ephemeral?(_), do: false

  @spec int_box?(String.t()) :: boolean()
  def int_box?(ref), do: is_binary(ref) and String.starts_with?(ref, @prefix_int)

  @spec materialize(String.t(), [String.t()], [String.t()], keyword(), boolean()) ::
          {String.t(), {[String.t()], [String.t()]}}
  def materialize(ref, prep, cleanup, opts, consume_args? \\ false)

  def materialize(ref, prep, cleanup, opts, consume_args?) when is_binary(ref) do
    if ephemeral?(ref) do
      if consume_args? and immortal_ephemeral_ref?(ref) do
        {immortal_ephemeral_c_ref(ref), {prep, cleanup}}
      else
        materialize_marker(ref, prep, cleanup, opts, consume_args?)
      end
    else
      {ref, {prep, cleanup}}
    end
  end

  @spec materialize_call_args([String.t()], keyword(), boolean()) ::
          {[String.t()], [String.t()], [String.t()]}
  def materialize_call_args(refs, opts, consume_args? \\ false) when is_list(refs) do
    Enum.map_reduce(refs, {[], []}, fn ref, {prep, cleanup} ->
      materialize(ref, prep, cleanup, opts, consume_args?)
    end)
    |> then(fn {c_args, {prep, cleanup}} -> {c_args, prep, cleanup} end)
  end

  @spec non_rc_scalar_assign(String.t(), String.t(), String.t()) :: String.t()
  def non_rc_scalar_assign(dest, function, scalar_arg)
      when is_binary(dest) and is_binary(function) and is_binary(scalar_arg) do
    """
    {
      ElmcValue *__box = NULL;
      {
        RC __alloc_rc = #{function}(&__box, #{scalar_arg});
        if (__alloc_rc != RC_SUCCESS) {
          ELMC_RC_LOG_FAIL(__alloc_rc, "#{function}", "allocation failed");
          #{dest} = NULL;
        } else {
          #{dest} = __box;
        }
      }
    }
    """
    |> String.trim()
  end

  @spec non_rc_scalar_return(String.t(), String.t(), non_neg_integer()) :: String.t()
  def non_rc_scalar_return(function, scalar_arg, owned_count)
      when is_binary(function) and is_binary(scalar_arg) and is_integer(owned_count) do
    lifo_fail =
      if owned_count > 0,
        do: "elmc_release_array_lifo(owned, #{owned_count});\n        ",
        else: ""

    lifo_ok =
      if owned_count > 0, do: "elmc_release_array_lifo(owned, #{owned_count});\n    ", else: ""

    """
    {
      ElmcValue *__ret = NULL;
      {
        RC __alloc_rc = #{function}(&__ret, #{scalar_arg});
        if (__alloc_rc != RC_SUCCESS) {
          ELMC_RC_LOG_FAIL(__alloc_rc, "#{function}", "allocation failed");
          #{lifo_fail}return NULL;
        }
      }
      #{lifo_ok}return __ret;
    }
    """
    |> String.trim()
  end

  defp materialize_marker(ref, prep, cleanup, opts, consume_args?) do
    var = "plan_ephemeral_box_#{System.unique_integer([:positive])}"
    rc? = Keyword.get(opts, :rc_required, false)

    {function, call_args} = decode_marker(ref)

    stmt =
      if rc? do
        """
        ElmcValue *#{var} = NULL;
        Rc = #{function}(&#{var}, #{call_args});
        CHECK_RC(Rc);
        """
        |> String.trim()
      else
        RcRuntimeEmit.non_rc_allocator_stmt(var, function, call_args, declare_out?: true)
      end

    cleanup_lines =
      if consume_args? do
        cleanup
      else
        cleanup ++ ["elmc_release(#{var});"]
      end

    {var, {prep ++ [stmt], cleanup_lines}}
  end

  @spec immortal_ephemeral_ref?(String.t()) :: boolean()
  defp immortal_ephemeral_ref?(ref) when is_binary(ref) do
    case decode_marker(ref) do
      {"elmc_new_int", "0"} -> true
      _ -> false
    end
  end

  @spec immortal_ephemeral_c_ref(String.t()) :: String.t()
  defp immortal_ephemeral_c_ref(_ref), do: "elmc_int_zero()"

  defp decode_marker(ref) do
    cond do
      String.starts_with?(ref, @prefix_int) ->
        [expr] = tail_parts(ref, @prefix_int)
        {"elmc_new_int", expr}

      String.starts_with?(ref, @prefix_bool) ->
        [expr] = tail_parts(ref, @prefix_bool)
        {"elmc_new_bool", expr}

      String.starts_with?(ref, @prefix_tuple2_ints) ->
        [left, right] = tail_parts(ref, @prefix_tuple2_ints)
        {"elmc_tuple2_ints", "#{left}, #{right}"}

      String.starts_with?(ref, @prefix_tuple2) ->
        [left, right] = tail_parts(ref, @prefix_tuple2)
        {"elmc_tuple2_take", "#{left}, #{right}"}

      String.starts_with?(ref, @prefix_string_len) ->
        [expr, len] = tail_parts(ref, @prefix_string_len)
        {"elmc_new_string_len", "#{expr}, #{len}"}

      String.starts_with?(ref, @prefix_string) ->
        [expr] = tail_parts(ref, @prefix_string)
        {"elmc_new_string", expr}

      true ->
        {"elmc_new_int", "0"}
    end
  end

  defp tail_parts(ref, prefix) do
    ref
    |> String.replace_prefix(prefix <> @sep, "")
    |> String.split(@sep, trim: true)
  end
end
