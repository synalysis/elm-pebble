defmodule Elmc.Backend.CCodegen.ListLoopCodegen do
  @moduledoc false

  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.ValueSlots

  defp val_expr(ref) when is_binary(ref), do: RcRuntimeEmit.value_expr(ref)

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
    "elmc_list_range" => "List.range",
    "elmc_list_find_first" => "List.head"
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

  @spec emit_length_native_count(String.t(), pos_integer(), keyword()) :: {String.t(), String.t()}
  def emit_length_native_count(list_var, loop_id, opts \\ []) do
    cursor = "list_length_cursor_#{loop_id}"
    node = "list_length_node_#{loop_id}"
    count = "list_length_count_#{loop_id}"

    code =
      case Keyword.get(opts, :repr, :dual) do
        :int_list ->
          """
            #{runtime_source_comment_line("elmc_list_length", 6)}elmc_int_t #{count} = 0;
            if (#{val_expr(list_var)} && #{val_expr(list_var)}->tag == ELMC_TAG_INT_LIST) {
              ElmcIntListPayload *_int_list_payload_#{loop_id} = (ElmcIntListPayload *)#{val_expr(list_var)}->payload;
              #{count} = _int_list_payload_#{loop_id} ? _int_list_payload_#{loop_id}->length : 0;
            }
          """

        :cons ->
          """
            #{runtime_source_comment_line("elmc_list_length", 6)}elmc_int_t #{count} = 0;
            ElmcValue *#{cursor} = #{val_expr(list_var)};
            while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
              ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
              #{count} += 1;
              #{cursor} = #{node}->tail;
            }
          """

        :native_linked ->
          """
            #{runtime_source_comment_line("elmc_list_length", 6)}elmc_int_t #{count} = 0;
            if (#{val_expr(list_var)} && #{val_expr(list_var)}->tag == ELMC_TAG_INT_LIST) {
              ElmcIntListPayload *_int_list_payload_#{loop_id} = (ElmcIntListPayload *)#{val_expr(list_var)}->payload;
              #{count} = _int_list_payload_#{loop_id} ? _int_list_payload_#{loop_id}->length : 0;
            } else {
              ElmcValue *#{cursor} = #{val_expr(list_var)};
              while (#{cursor} && #{cursor}->tag == ELMC_TAG_INT_SPINE && #{cursor}->payload != NULL) {
                #{count} += 1;
                #{cursor} = ((ElmcIntSpine *)#{cursor}->payload)->tail;
              }
            }
          """

        _ ->
          """
            #{runtime_source_comment_line("elmc_list_length", 6)}elmc_int_t #{count} = 0;
            if (#{val_expr(list_var)} && #{val_expr(list_var)}->tag == ELMC_TAG_INT_LIST) {
              ElmcIntListPayload *_int_list_payload_#{loop_id} = (ElmcIntListPayload *)#{val_expr(list_var)}->payload;
              #{count} = _int_list_payload_#{loop_id} ? _int_list_payload_#{loop_id}->length : 0;
            } else {
              ElmcValue *#{cursor} = #{val_expr(list_var)};
              while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
                ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
                #{count} += 1;
                #{cursor} = #{node}->tail;
              }
            }
          """
      end

    {code, count}
  end

  @spec emit_repeat_inline_loop(String.t(), String.t(), pos_integer(), map()) ::
          {String.t(), String.t()}
  def emit_repeat_inline_loop(count_ref, value_ref, loop_id, env \\ %{}) do
    acc = "list_repeat_acc_#{loop_id}"

    if value_ref == "elmc_int_zero()" do
      {emit_int_zero_repeat_from_count(count_ref, acc, loop_id, env), acc}
    else
      emit_repeat_inline_loop_cons(count_ref, value_ref, loop_id, acc, env)
    end
  end

  defp emit_repeat_inline_loop_cons(count_ref, value_ref, loop_id, acc, env) do
    index_var = "list_repeat_i_#{loop_id}"

    {cons_var, cons_body, post_loop} =
      if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
        {cons_ref, _} = ValueSlots.alloc()

        cons_body =
          """
          Rc = elmc_list_cons(#{RcRuntimeEmit.allocator_out_arg(cons_ref)}, #{value_ref}, #{acc});
          CHECK_RC(Rc);
          """

        {cons_ref, cons_body, "\n    CHECK_RC(Rc);"}
      else
        cons_ref = "list_repeat_cons_#{loop_id}"

        cons_body =
          RcRuntimeEmit.list_cons_retain_assign(
            cons_ref,
            "#{value_ref}, #{acc}",
            env,
            return_on_fail?: false
          )

        {cons_ref, cons_body, ""}
      end

    loop_body =
      if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
        """
        #{cons_body}
        #{ValueSlots.release_owned_eager(acc)}
        #{acc} = #{cons_var};
        #{ValueSlots.abandon_stmt(cons_var)}
        """
      else
        """
        #{cons_body}
        #{ValueSlots.release_stmt(acc)}
        #{acc} = #{cons_var};
        """
      end

    code = """
      #{runtime_source_comment_line("elmc_list_repeat", 6)}ElmcValue *#{acc} = elmc_list_nil();
      for (elmc_int_t #{index_var} = 0; #{index_var} < #{count_ref}; #{index_var}++) {
        #{loop_body}
      }#{post_loop}
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

  @spec emit_int_list_cons_assign(
          Types.compile_env(),
          String.t(),
          String.t(),
          String.t(),
          pos_integer()
        ) :: String.t()
  def emit_int_list_cons_assign(env, out, head, tail, loop_id, opts \\ []) do
    head = val_expr(head)
    tail = val_expr(tail)
    buf = "int_list_cons_buf_#{loop_id}"
    len = "int_list_cons_tail_len_#{loop_id}"

    declare? =
      Keyword.get(
        opts,
        :declare_out?,
        not ValueSlots.owned_ref?(out) and not RcRuntimeEmit.predeclared_out_slot?(env, out) and
          not RcRuntimeEmit.function_out_ref?(out)
      )

    init =
      if declare? do
        "#{ValueSlots.boxed_null_decl(out)}\n"
      else
        ""
      end

    fast_path_releases =
      if Keyword.get(opts, :fast_path_release_operands?, false) do
        """
        #{operand_release_after_cons(tail)}
        if (#{head} != elmc_int_zero()) { #{operand_release_after_cons(head)} }
        """
      else
        ""
      end

    fast_path_assign =
      RcRuntimeEmit.mutually_exclusive_assign_into(
        env,
        out,
        "elmc_list_from_int_array",
        "#{buf}, #{len} + 1"
      )

    slow_path_assign =
      RcRuntimeEmit.mutually_exclusive_allocator_assign(
        env,
        out,
        "elmc_list_cons",
        "#{head}, #{tail}",
        declare_out?: false
      )

    if ValueSlots.owned_ref?(out), do: ValueSlots.mark_written(out)

    """
    #{init}if (#{tail} && #{tail}->tag == ELMC_TAG_INT_LIST && #{head} && (#{head}->tag == ELMC_TAG_INT || #{head}->tag == ELMC_TAG_CHAR)) {
      ElmcIntListPayload *_ilp_#{loop_id} = (ElmcIntListPayload *)#{tail}->payload;
      int #{len} = _ilp_#{loop_id} ? _ilp_#{loop_id}->length : 0;
      elmc_int_t #{buf}[1 + #{len}];
      #{buf}[0] = elmc_as_int(#{head});
      for (int _ii_#{loop_id} = 0; _ii_#{loop_id} < #{len}; _ii_#{loop_id}++) {
        #{buf}[_ii_#{loop_id} + 1] = _ilp_#{loop_id}->values[_ii_#{loop_id}];
      }
      #{fast_path_assign}
    #{fast_path_releases}
    } else {
      #{slow_path_assign}
    #{fast_path_releases}
    }
    """
  end

  @spec emit_int_zero_repeat_from_count(String.t(), String.t(), pos_integer(), map()) :: String.t()
  def emit_int_zero_repeat_from_count(count_ref, out, loop_id, env) do
    buf = "list_repeat_zero_buf_#{loop_id}"

    """
    ElmcValue *#{out} = NULL;
    if (#{count_ref} <= 0) {
      #{RcRuntimeEmit.assign_into(env, out, "elmc_list_from_int_array", "NULL, 0")}
    } else {
      elmc_int_t #{buf}[#{count_ref}];
      for (elmc_int_t _zi_#{loop_id} = 0; _zi_#{loop_id} < #{count_ref}; _zi_#{loop_id}++) {
        #{buf}[_zi_#{loop_id}] = 0;
      }
      #{RcRuntimeEmit.assign_into(env, out, "elmc_list_from_int_array", "#{buf}, #{count_ref}")}
    }
    """
  end

  @spec forward_head_name(pos_integer()) :: String.t()
  def forward_head_name(loop_id), do: forward_head(loop_id)

  @spec emit_forward_list_init(pos_integer(), map()) :: {String.t(), String.t()}
  def emit_forward_list_init(loop_id, env \\ %{}) do
    if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
      {head_ref, _} = ValueSlots.alloc()
      tail = forward_tail(loop_id)

      code = """
        #{head_ref} = elmc_list_nil();
        ElmcValue **#{tail} = &#{head_ref};
      """

      {code, head_ref}
    else
      head = forward_head(loop_id)
      tail = forward_tail(loop_id)

      code = """
        ElmcValue *#{head} = elmc_list_nil();
        ElmcValue **#{tail} = &#{head};
      """

      {code, head}
    end
  end

  @spec emit_forward_list_append(pos_integer(), String.t(), keyword()) :: String.t()
  def emit_forward_list_append(loop_id, item_expr, opts \\ []) do
    append_id = Keyword.get(opts, :append_id, loop_id)
    tail = forward_tail(loop_id)
    owned? = Keyword.get(opts, :owned, false)
    env = Keyword.get(opts, :env, %{})

    cons =
      if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
        {cell_ref, _} = ValueSlots.alloc()
        cell_ref
      else
        forward_cell(append_id)
      end

    cons_body =
      RcRuntimeEmit.list_cons_retain_assign(
        cons,
        "#{item_expr}, elmc_list_nil()",
        env,
        return_on_fail?: false
      )

    release_owned =
      if owned? and owned_forward_item_expr?(item_expr) do
        ValueSlots.release_stmt(item_expr) <> "\n        "
      else
        ""
      end

    abandon_cons =
      if RcRuntimeEmit.rc_allocator_emit_mode?(env) and ValueSlots.owned_ref?(cons) do
        ValueSlots.abandon_stmt(cons) <> "\n        "
      else
        ""
      end

    """
        #{cons_body}
        #{release_owned}if (#{cons}) {
          *#{tail} = #{cons};
          #{tail} = &((ElmcCons *)#{cons}->payload)->tail;
        }
        #{abandon_cons}
    """
  end

  @spec finalize_forward_cursor_list(pos_integer(), String.t(), keyword()) :: String.t()
  def finalize_forward_cursor_list(_loop_id, out_var, opts \\ []) do
    env = Keyword.get(opts, :env, %{})
    head = Keyword.fetch!(opts, :head)

    cond do
      RcRuntimeEmit.rc_allocator_emit_mode?(env) and ValueSlots.owned_ref?(out_var) and
          ValueSlots.owned_ref?(head) ->
        RcRuntimeEmit.transfer_assignment(out_var, head)

      RcRuntimeEmit.rc_allocator_emit_mode?(env) and ValueSlots.owned_ref?(out_var) ->
        RcRuntimeEmit.assign_stmt(out_var, head)

      true ->
        "ElmcValue *#{out_var} = #{head};\n"
    end
  end

  @spec emit_forward_list_append_sublist(pos_integer(), String.t(), keyword()) :: String.t()
  def emit_forward_list_append_sublist(loop_id, sublist_expr, opts \\ []) when is_binary(sublist_expr) do
    env = Keyword.get(opts, :env, %{})
    sub_cursor = "list_concat_map_sub_cursor_#{loop_id}"
    sub_node = "list_concat_map_sub_node_#{loop_id}"

    """
    ElmcValue *#{sub_cursor} = #{val_expr(sublist_expr)};
    while (#{sub_cursor} && #{sub_cursor}->tag == ELMC_TAG_LIST && #{sub_cursor}->payload != NULL) {
      ElmcCons *#{sub_node} = (ElmcCons *)#{sub_cursor}->payload;
      #{emit_forward_list_append(loop_id, "#{sub_node}->head", env: env)}
      #{sub_cursor} = #{sub_node}->tail;
    }
    """
  end

  @spec forward_head(pos_integer()) :: String.t()
  defp forward_head(loop_id), do: "list_fwd_head_#{loop_id}"

  @spec forward_tail(pos_integer()) :: String.t()
  defp forward_tail(loop_id), do: "list_fwd_tail_#{loop_id}"

  @spec forward_cell(pos_integer()) :: String.t()
  defp forward_cell(loop_id), do: "list_fwd_cell_#{loop_id}"

  # `elmc_list_cons` retains its head; owned forward-build loops already hold one ref.
  defp owned_forward_item_expr?(item_expr) when is_binary(item_expr) do
    Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, item_expr)
  end

  @spec emit_ascending_int_range_loop(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: String.t()
  @spec emit_native_list_int_head_loop(String.t(), pos_integer(), String.t(), String.t(), keyword()) ::
          String.t()
  def emit_native_list_int_head_loop(list_ref, loop_id, head_native_var, inner_body, opts \\ [])
      when is_binary(list_ref) and is_binary(head_native_var) and is_binary(inner_body) do
    case Keyword.get(opts, :repr, :dual) do
      :int_list ->
        emit_native_list_int_head_loop_only(list_ref, loop_id, head_native_var, inner_body)

      :float_list ->
        emit_native_float_list_head_loop_only(list_ref, loop_id, head_native_var, inner_body)

      :record_seq ->
        emit_native_record_seq_head_loop_only(list_ref, loop_id, head_native_var, inner_body)

      :native_linked ->
        emit_native_linked_int_head_loop(list_ref, loop_id, head_native_var, inner_body)

      :cons ->
        emit_native_list_cons_head_loop_only(list_ref, loop_id, head_native_var, inner_body)

      _ ->
        emit_native_list_int_head_loop_dual(list_ref, loop_id, head_native_var, inner_body)
    end
  end

  defp emit_native_linked_int_head_loop(list_ref, loop_id, head_native_var, inner_body) do
    cursor = "list_spine_cursor_#{loop_id}"

    """
    if (#{val_expr(list_ref)} && #{val_expr(list_ref)}->tag == ELMC_TAG_INT_LIST) {
      ElmcIntListPayload *_ilp_#{loop_id} = (ElmcIntListPayload *)#{val_expr(list_ref)}->payload;
      int _ilen_#{loop_id} = _ilp_#{loop_id} ? _ilp_#{loop_id}->length : 0;
      for (int _ii_#{loop_id} = 0; _ii_#{loop_id} < _ilen_#{loop_id}; _ii_#{loop_id}++) {
        const elmc_int_t #{head_native_var} = _ilp_#{loop_id}->values[_ii_#{loop_id}];
    #{inner_body}
      }
    } else {
      ElmcValue *#{cursor} = #{val_expr(list_ref)};
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_INT_SPINE && #{cursor}->payload != NULL) {
        const elmc_int_t #{head_native_var} = ((ElmcIntSpine *)#{cursor}->payload)->head;
    #{inner_body}
        #{cursor} = ((ElmcIntSpine *)#{cursor}->payload)->tail;
      }
    }
    """
  end

  defp emit_native_list_int_head_loop_only(list_ref, loop_id, head_native_var, inner_body) do
    """
    if (#{val_expr(list_ref)} && #{val_expr(list_ref)}->tag == ELMC_TAG_INT_LIST) {
      ElmcIntListPayload *_ilp_#{loop_id} = (ElmcIntListPayload *)#{val_expr(list_ref)}->payload;
      int _ilen_#{loop_id} = _ilp_#{loop_id} ? _ilp_#{loop_id}->length : 0;
      for (int _ii_#{loop_id} = 0; _ii_#{loop_id} < _ilen_#{loop_id}; _ii_#{loop_id}++) {
        const elmc_int_t #{head_native_var} = _ilp_#{loop_id}->values[_ii_#{loop_id}];
    #{inner_body}
      }
    }
    """
  end

  defp emit_native_list_cons_head_loop_only(list_ref, loop_id, head_native_var, inner_body) do
    cursor = "list_walk_cursor_#{loop_id}"
    node = "list_walk_node_#{loop_id}"

    """
    ElmcValue *#{cursor} = #{val_expr(list_ref)};
    while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
      ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
      const elmc_int_t #{head_native_var} = elmc_as_int(#{node}->head);
    #{inner_body}
      #{cursor} = #{node}->tail;
    }
    """
  end

  defp emit_native_list_int_head_loop_dual(list_ref, loop_id, head_native_var, inner_body) do
    cursor = "list_walk_cursor_#{loop_id}"
    node = "list_walk_node_#{loop_id}"

    """
    if (#{val_expr(list_ref)} && #{val_expr(list_ref)}->tag == ELMC_TAG_INT_LIST) {
      ElmcIntListPayload *_ilp_#{loop_id} = (ElmcIntListPayload *)#{val_expr(list_ref)}->payload;
      int _ilen_#{loop_id} = _ilp_#{loop_id} ? _ilp_#{loop_id}->length : 0;
      for (int _ii_#{loop_id} = 0; _ii_#{loop_id} < _ilen_#{loop_id}; _ii_#{loop_id}++) {
        const elmc_int_t #{head_native_var} = _ilp_#{loop_id}->values[_ii_#{loop_id}];
    #{inner_body}
      }
    } else {
      ElmcValue *#{cursor} = #{val_expr(list_ref)};
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
        ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
        const elmc_int_t #{head_native_var} = elmc_as_int(#{node}->head);
    #{inner_body}
        #{cursor} = #{node}->tail;
      }
    }
    """
  end

  @doc false
  @spec emit_boxed_head_list_walk(String.t(), pos_integer(), String.t(), String.t(), keyword()) ::
          String.t()
  def emit_boxed_head_list_walk(list_ref, loop_id, head_var, inner_body, opts \\ [])
      when is_binary(list_ref) and is_binary(head_var) and is_binary(inner_body) do
    case Keyword.get(opts, :repr, :dual) do
      :int_list ->
        emit_boxed_head_int_list_walk_only(list_ref, loop_id, head_var, inner_body, opts)

      :cons ->
        emit_boxed_head_cons_walk_only(list_ref, loop_id, head_var, inner_body)

      :native_linked ->
        emit_boxed_head_native_linked_walk(list_ref, loop_id, head_var, inner_body, opts)

      :record_seq ->
        emit_boxed_head_record_seq_walk_only(list_ref, loop_id, head_var, inner_body)

      _ ->
        emit_boxed_head_list_walk_dual(list_ref, loop_id, head_var, inner_body, opts)
    end
  end

  defp int_list_head_take(head_var, list_expr, env) do
    RcRuntimeEmit.check_rc_take(head_var, "elmc_new_int", list_expr, env)
  end

  defp int_spine_head_take(head_var, list_expr, env) do
    if RcRuntimeEmit.rc_allocator_emit_mode?(env) do
      RcRuntimeEmit.check_rc_take(head_var, "elmc_int_spine_head_boxed", list_expr, env)
    else
      "ElmcValue *#{head_var} = elmc_int_spine_head_boxed_take(#{list_expr});"
    end
  end

  defp emit_boxed_head_int_list_walk_only(list_ref, loop_id, head_var, inner_body, opts) do
    env = Keyword.get(opts, :env, %{})
    """
    if (#{val_expr(list_ref)} && #{val_expr(list_ref)}->tag == ELMC_TAG_INT_LIST) {
      ElmcIntListPayload *_ilp_#{loop_id} = (ElmcIntListPayload *)#{val_expr(list_ref)}->payload;
      int _ilen_#{loop_id} = _ilp_#{loop_id} ? _ilp_#{loop_id}->length : 0;
      for (int _ii_#{loop_id} = 0; _ii_#{loop_id} < _ilen_#{loop_id}; _ii_#{loop_id}++) {
        #{int_list_head_take(head_var, "_ilp_#{loop_id}->values[_ii_#{loop_id}]", env)}
    #{inner_body}
        #{ValueSlots.release_stmt(head_var)};
      }
      #{RcRuntimeEmit.loop_exit_check_rc(env)}
    }
    """
  end

  defp emit_boxed_head_cons_walk_only(list_ref, loop_id, head_var, inner_body) do
    cursor = "list_walk_cursor_#{loop_id}"
    node = "list_walk_node_#{loop_id}"

    """
    ElmcValue *#{cursor} = #{val_expr(list_ref)};
    while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
      ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
      ElmcValue *#{head_var} = #{node}->head;
    #{inner_body}
      #{cursor} = #{node}->tail;
    }
    """
  end

  defp emit_boxed_head_native_linked_walk(list_ref, loop_id, head_var, inner_body, opts) do
    env = Keyword.get(opts, :env, %{})
    cursor = "list_spine_cursor_#{loop_id}"

    """
    if (#{val_expr(list_ref)} && #{val_expr(list_ref)}->tag == ELMC_TAG_INT_LIST) {
      ElmcIntListPayload *_ilp_#{loop_id} = (ElmcIntListPayload *)#{val_expr(list_ref)}->payload;
      int _ilen_#{loop_id} = _ilp_#{loop_id} ? _ilp_#{loop_id}->length : 0;
      for (int _ii_#{loop_id} = 0; _ii_#{loop_id} < _ilen_#{loop_id}; _ii_#{loop_id}++) {
        #{int_list_head_take(head_var, "_ilp_#{loop_id}->values[_ii_#{loop_id}]", env)}
    #{inner_body}
        #{ValueSlots.release_stmt(head_var)};
      }
      #{RcRuntimeEmit.loop_exit_check_rc(env)}
    } else {
      ElmcValue *#{cursor} = #{val_expr(list_ref)};
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_INT_SPINE && #{cursor}->payload != NULL) {
        #{int_spine_head_take(head_var, cursor, env)}
    #{inner_body}
        #{ValueSlots.release_stmt(head_var)};
        #{cursor} = ((ElmcIntSpine *)#{cursor}->payload)->tail;
      }
    }
    """
  end

  defp emit_boxed_head_record_seq_walk_only(list_ref, loop_id, head_var, inner_body) do
    """
    if (#{val_expr(list_ref)} && #{val_expr(list_ref)}->tag == ELMC_TAG_RECORD_SEQ) {
      ElmcRecordSeqPayload *_rsp_#{loop_id} = (ElmcRecordSeqPayload *)#{val_expr(list_ref)}->payload;
      int _rlen_#{loop_id} = _rsp_#{loop_id} ? _rsp_#{loop_id}->length : 0;
      for (int _ri_#{loop_id} = 0; _ri_#{loop_id} < _rlen_#{loop_id}; _ri_#{loop_id}++) {
        ElmcValue *#{head_var} = _rsp_#{loop_id}->items[_ri_#{loop_id}];
    #{inner_body}
      }
    }
    """
  end

  defp emit_boxed_head_list_walk_dual(list_ref, loop_id, head_var, inner_body, opts) do
    env = Keyword.get(opts, :env, %{})
    cursor = "list_walk_cursor_#{loop_id}"
    node = "list_walk_node_#{loop_id}"

    """
    if (#{val_expr(list_ref)} && #{val_expr(list_ref)}->tag == ELMC_TAG_INT_LIST) {
      ElmcIntListPayload *_ilp_#{loop_id} = (ElmcIntListPayload *)#{val_expr(list_ref)}->payload;
      int _ilen_#{loop_id} = _ilp_#{loop_id} ? _ilp_#{loop_id}->length : 0;
      for (int _ii_#{loop_id} = 0; _ii_#{loop_id} < _ilen_#{loop_id}; _ii_#{loop_id}++) {
        #{int_list_head_take(head_var, "_ilp_#{loop_id}->values[_ii_#{loop_id}]", env)}
    #{inner_body}
        #{ValueSlots.release_stmt(head_var)};
      }
      #{RcRuntimeEmit.loop_exit_check_rc(env)}
    } else {
      ElmcValue *#{cursor} = #{val_expr(list_ref)};
      while (#{cursor} && #{cursor}->tag == ELMC_TAG_LIST && #{cursor}->payload != NULL) {
        ElmcCons *#{node} = (ElmcCons *)#{cursor}->payload;
        ElmcValue *#{head_var} = #{node}->head;
    #{inner_body}
        #{cursor} = #{node}->tail;
      }
    }
    """
  end

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

  defp emit_native_float_list_head_loop_only(list_ref, loop_id, head_native_var, inner_body) do
    """
    if (#{val_expr(list_ref)} && #{val_expr(list_ref)}->tag == ELMC_TAG_FLOAT_LIST) {
      ElmcFloatListPayload *_flp_#{loop_id} = (ElmcFloatListPayload *)#{val_expr(list_ref)}->payload;
      int _flen_#{loop_id} = _flp_#{loop_id} ? _flp_#{loop_id}->length : 0;
      for (int _fi_#{loop_id} = 0; _fi_#{loop_id} < _flen_#{loop_id}; _fi_#{loop_id}++) {
        const double #{head_native_var} = _flp_#{loop_id}->values[_fi_#{loop_id}];
    #{inner_body}
      }
    }
    """
  end

  defp emit_native_record_seq_head_loop_only(list_ref, loop_id, head_var, inner_body) do
    """
    if (#{val_expr(list_ref)} && #{val_expr(list_ref)}->tag == ELMC_TAG_RECORD_SEQ) {
      ElmcRecordSeqPayload *_rsp_#{loop_id} = (ElmcRecordSeqPayload *)#{val_expr(list_ref)}->payload;
      int _rlen_#{loop_id} = _rsp_#{loop_id} ? _rsp_#{loop_id}->length : 0;
      for (int _ri_#{loop_id} = 0; _ri_#{loop_id} < _rlen_#{loop_id}; _ri_#{loop_id}++) {
        ElmcValue *#{head_var} = _rsp_#{loop_id}->items[_ri_#{loop_id}];
    #{inner_body}
      }
    }
    """
  end

  defp operand_release_after_cons(var) when is_binary(var) do
    if ValueSlots.owned_ref?(var) do
      ValueSlots.release_owned_eager(var)
    else
      ValueSlots.release_stmt(var)
    end
  end
end
