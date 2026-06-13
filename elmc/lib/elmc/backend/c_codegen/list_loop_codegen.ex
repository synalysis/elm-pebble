defmodule Elmc.Backend.CCodegen.ListLoopCodegen do
  @moduledoc false

  alias Elmc.Backend.CCodegen.RcRuntimeEmit

  alias Elmc.Backend.CCodegen.Types

  @runtime_source_comments %{
    "elmc_list_all" => "List.all",
    "elmc_list_any" => "List.any",
    "elmc_list_foldl" => "List.foldl",
    "elmc_list_map" => "List.map",
    "elmc_list_filter" => "List.filter",
    "elmc_list_filter_map" => "List.filterMap",
    "elmc_list_indexed_map" => "List.indexedMap",
    "elmc_list_length" => "List.length",
    "elmc_list_repeat" => "List.repeat",
    "elmc_list_range" => "List.range"
  }

  @spec runtime_source_comment(String.t()) :: String.t() | nil
  def runtime_source_comment(runtime_function) when is_binary(runtime_function) do
    Map.get(@runtime_source_comments, runtime_function)
  end

  @spec runtime_source_comment_line(String.t(), non_neg_integer()) :: String.t()
  def runtime_source_comment_line(runtime_function, indent \\ 8)
      when is_binary(runtime_function) and is_integer(indent) do
    case runtime_source_comment(runtime_function) do
      nil -> ""
      label -> String.duplicate(" ", indent) <> "// #{label}\n"
    end
  end

  @spec emit_length_native_count(String.t(), pos_integer()) :: {String.t(), String.t()}
  def emit_length_native_count(list_var, loop_id) do
    cursor = "list_length_cursor_#{loop_id}"
    node = "list_length_node_#{loop_id}"
    count = "list_length_count_#{loop_id}"

    code = """
      #{runtime_source_comment_line("elmc_list_length", 6)}elmc_int_t #{count} = 0;
      ElmcValue *#{cursor} = #{list_var};
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
        ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
        #{count} += 1;
        #{cursor} = #{node}->tail;
      }
    """

    {code, count}
  end

  @spec emit_repeat_inline_loop(String.t(), String.t(), pos_integer(), map()) ::
          {String.t(), String.t()}
  def emit_repeat_inline_loop(count_ref, value_ref, loop_id, env \\ %{}) do
    index_var = "list_repeat_i_#{loop_id}"
    acc = "list_repeat_acc_#{loop_id}"
    cons = "list_repeat_cons_#{loop_id}"

    code = """
      #{runtime_source_comment_line("elmc_list_repeat", 6)}ElmcValue *#{acc} = elmc_list_nil();
      for (elmc_int_t #{index_var} = 0; #{index_var} < #{count_ref}; #{index_var}++) {
        #{RcRuntimeEmit.list_cons_retain_assign(cons, "#{value_ref}, #{acc}", env)}
        elmc_release(#{acc});
        #{acc} = #{cons};
      }
      if (!#{acc}) #{acc} = elmc_list_nil();
    """

    {code, acc}
  end

  @spec unwrap_list_length_expr(Types.ir_expr()) :: {:ok, Types.ir_expr()} | :error
  def unwrap_list_length_expr(%{op: :runtime_call, function: "elmc_list_length", args: [list]}),
    do: {:ok, list}

  def unwrap_list_length_expr(%{op: :qualified_call, target: target, args: [list]})
      when target in ["List.length", "Elm.Kernel.List.length"],
      do: {:ok, list}

  def unwrap_list_length_expr(%{op: :call, name: "length", args: [list]}), do: {:ok, list}

  def unwrap_list_length_expr(_expr), do: :error

  @spec emit_forward_list_init(pos_integer()) :: {String.t(), String.t()}
  def emit_forward_list_init(loop_id) do
    head = forward_head(loop_id)
    tail = forward_tail(loop_id)

    code = """
      ElmcValue *#{head} = elmc_list_nil();
      ElmcValue **#{tail} = &#{head};
    """

    {code, head}
  end

  @spec emit_forward_list_append(pos_integer(), String.t(), keyword()) :: String.t()
  def emit_forward_list_append(loop_id, item_expr, opts \\ []) do
    cell = forward_cell(loop_id)
    tail = forward_tail(loop_id)
    owned? = Keyword.get(opts, :owned, false)
    env = Keyword.get(opts, :env, %{})

    cons =
      if owned? do
        RcRuntimeEmit.fusion_assign(cell, "elmc_list_cons", "#{item_expr}, elmc_list_nil()", env)
      else
        RcRuntimeEmit.list_cons_retain_assign(
          cell,
          "#{item_expr}, elmc_list_nil()",
          env,
          return_on_fail?: false
        )
      end

    """
        #{cons}
        *#{tail} = #{cell};
        #{tail} = &((ElmcCons *)#{cell}->payload)->tail;
    """
  end

  @spec finalize_forward_cursor_list(pos_integer(), String.t()) :: String.t()
  def finalize_forward_cursor_list(loop_id, out_var) do
    "ElmcValue *#{out_var} = #{forward_head(loop_id)};\n"
  end

  @spec forward_head(pos_integer()) :: String.t()
  defp forward_head(loop_id), do: "list_fwd_head_#{loop_id}"

  @spec forward_tail(pos_integer()) :: String.t()
  defp forward_tail(loop_id), do: "list_fwd_tail_#{loop_id}"

  @spec forward_cell(pos_integer()) :: String.t()
  defp forward_cell(loop_id), do: "list_fwd_cell_#{loop_id}"

  @spec emit_ascending_int_range_loop(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: String.t()
  def emit_ascending_int_range_loop(first_ref, last_ref, item_var, step_var, body) do
    """
    if (#{first_ref} <= #{last_ref}) {
      elmc_int_t #{step_var} = 1;
      for (elmc_int_t #{item_var} = #{first_ref}; ; #{item_var} += #{step_var}) {
    #{body}
        if (#{item_var} == #{last_ref}) break;
      }
    }
    """
  end

  @spec emit_descending_int_range_loop(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: String.t()
  def emit_descending_int_range_loop(first_ref, last_ref, item_var, step_var, body) do
    """
    if (#{first_ref} <= #{last_ref}) {
      elmc_int_t #{step_var} = -1;
      for (elmc_int_t #{item_var} = #{last_ref}; ; #{item_var} += #{step_var}) {
    #{body}
        if (#{item_var} == #{first_ref}) break;
      }
    }
    """
  end
end
