defmodule Elmc.Backend.CCodegen.FunctionSplit do
  @moduledoc false

  alias Elmc.Backend.CCodegen.AppendSegments
  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.LetAnalysis
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.StackEstimate
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.ValueSlots

  @risk_threshold 10
  @min_segments 4
  @segments_per_part 3

  @spec try_emit_native_split(
          Types.function_declaration(),
          String.t(),
          Types.function_decl_map(),
          Types.compile_env(),
          [Types.native_function_arg_kind()],
          String.t(),
          String.t(),
          String.t(),
          String.t()
        ) :: {:ok, String.t()} | :error
  def try_emit_native_split(
        decl,
        module_name,
        decl_map,
        env,
        _arg_kinds,
        c_name,
        entry_probe,
        exit_probe,
        unused_casts
      ) do
    with true <- split_enabled?(),
         true <- split_candidate?(decl),
         {:ok, parts} <- plan_parts(decl.expr, decl.args || []),
         {:ok, native_def} <-
           build_split_native(
             decl,
             module_name,
             decl_map,
             env,
             c_name,
             parts,
             entry_probe,
             exit_probe,
             unused_casts
           ) do
      {:ok, native_def}
    else
      _ -> :error
    end
  end

  defp split_enabled? do
    opts = Process.get(:elmc_codegen_opts, [])

    pebble_int32? =
      cond do
        is_list(opts) -> Keyword.get(opts, :pebble_int32) == true
        is_map(opts) -> Map.get(opts, :pebble_int32) == true
        true -> false
      end

    split_opt? =
      cond do
        is_list(opts) -> Keyword.get(opts, :function_split, true) != false
        is_map(opts) -> Map.get(opts, :function_split, true) != false
        true -> true
      end

    pebble_int32? and split_opt?
  end

  defp split_candidate?(decl) do
    StackEstimate.ir_function_score(decl) >= @risk_threshold
  end

  @doc false
  @spec plan_parts_for_test(Types.ir_expr(), [String.t()]) ::
          {:ok, [{let_names :: [String.t()], part_expr :: Types.ir_expr()}]} | :error
  def plan_parts_for_test(expr, arg_names) do
    {body, lets} = peel_lets(expr)

    with {:ok, segments} <- AppendSegments.collect(body),
         true <- length(segments) >= @min_segments do
      parts =
        segments
        |> Enum.chunk_every(@segments_per_part)
        |> Enum.map(fn part_segments ->
          part_lets = required_lets(lets, part_segments, arg_names)
          {Enum.map(part_lets, fn {name, _} -> to_string(name) end),
           rebuild_lets(part_lets, fold_append(part_segments))}
        end)

      case parts do
        [_single] -> :error
        parts -> {:ok, parts}
      end
    else
      _ -> :error
    end
  end

  @spec plan_parts(Types.ir_expr(), [String.t()]) :: {:ok, [Types.ir_expr()]} | :error
  defp plan_parts(expr, arg_names) do
    {body, lets} = peel_lets(expr)

    with {:ok, segments} <- AppendSegments.collect(body),
         true <- length(segments) >= @min_segments do
      segments
      |> Enum.chunk_every(@segments_per_part)
      |> Enum.map(fn part_segments ->
        part_lets = required_lets(lets, part_segments, arg_names)
        rebuild_lets(part_lets, fold_append(part_segments))
      end)
      |> case do
        [_single] -> :error
        parts -> {:ok, parts}
      end
    else
      _ -> :error
    end
  end

  defp build_split_native(
         decl,
         module_name,
         decl_map,
         parent_env,
         c_name,
         parts,
         entry_probe,
         exit_probe,
         unused_casts
       ) do
    arg_bindings = FunctionEmit.c_arg_bindings(decl.args || [])
    arg_kinds = NativeFunctionCall.arg_kinds(decl, module_name, decl_map)
    fused_args = fused_call_args(arg_bindings, arg_kinds)

    {part_defs, merge_lines, _} =
      Enum.reduce(Enum.with_index(parts), {"", [], 0}, fn {part_expr, index}, {defs, merge, _} ->
        part_name = "#{decl.name}__part#{index}"
        part_c_name = "#{c_name}_part#{index}"

        part_def =
          emit_part_native(
            decl,
            module_name,
            decl_map,
            parent_env,
            part_name,
            part_c_name,
            part_expr,
            entry_probe,
            exit_probe,
            unused_casts
          )

        acc_var = "split_acc_#{index}"
        part_var = "split_part_#{index}"

        merge =
          if index == 0 do
            merge ++
              [
                "ElmcValue *#{acc_var} = NULL;",
                "Rc = #{part_c_name}_native(&#{acc_var}, #{fused_args});",
                "CHECK_RC(Rc);"
              ]
          else
            prev_acc = "split_acc_#{index - 1}"
            merged = "split_merged_#{index}"

            merge ++
              [
                "ElmcValue *#{part_var} = NULL;",
                "Rc = #{part_c_name}_native(&#{part_var}, #{fused_args});",
                "CHECK_RC(Rc);",
                "ElmcValue *#{merged} = NULL;",
                "Rc = elmc_list_append(&#{merged}, #{prev_acc}, #{part_var});",
                "CHECK_RC(Rc);",
                "elmc_release(#{prev_acc});",
                "elmc_release(#{part_var});",
                "ElmcValue *#{acc_var} = #{merged};"
              ]
          end

        {defs <> part_def <> "\n", merge, index}
      end)

    params = NativeFunctionCall.params(decl, module_name, decl_map)
    last_acc = "split_acc_#{length(parts) - 1}"

    orchestrator =
      merge_lines
      |> Kernel.++([RcRuntimeEmit.publish_function_out_from(last_acc)])
      |> Enum.join("\n    ")

    native_def = """
    #{part_defs}
    static RC #{c_name}_native(ElmcValue **out, #{params}) {
      #{unused_casts}
      RC Rc = RC_SUCCESS;
      CATCH_BEGIN
      #{orchestrator}
      CATCH_END;
      return Rc;
    }
    """

    {:ok, native_def}
  end

  defp emit_part_native(
         decl,
         module_name,
         decl_map,
         parent_env,
         part_name,
         part_c_name,
         part_expr,
         entry_probe,
         exit_probe,
         unused_casts
       ) do
    ValueSlots.reset(epilogue_lifo: true)
    RecordCompile.reset_borrowed_field_refs()

    env =
      parent_env
      |> Map.put(:__function_name__, part_name)
      |> Map.put(
        :__function_analysis__,
        LetAnalysis.analyze_function_expr(part_expr, module_name, decl_map)
      )
      |> Map.put(:__rc_catch__, true)
      |> RcRuntimeEmit.function_tail_env()

    {body_code, body_var, _counter} = Host.compile_expr(part_expr, env, 0)

    unless RcRuntimeEmit.function_out_ref?(body_var), do: ValueSlots.track(body_var)

    body_text =
      [entry_probe, body_code, exit_probe]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    owned_decls = ValueSlots.owned_declaration()
    failure_cleanup = ValueSlots.failure_cleanup()
    needs_catch? = rc_body_needs_catch?(body_text) or owned_decls != ""

    {hoisted_decl, catch_body} = prepare_catch_body(body_text, body_var)

    catch_body =
      if needs_catch? and not RcRuntimeEmit.function_out_ref?(body_var) do
        catch_body <> "\n    " <> RcRuntimeEmit.publish_function_out_from(body_var)
      else
        catch_body
      end

    prefix =
      ["RC Rc = RC_SUCCESS;"] ++
        List.wrap(hoisted_decl) ++
        List.wrap(owned_decls) ++
        List.wrap(unused_casts)

    core =
      if needs_catch? do
        """
        CATCH_BEGIN
        #{catch_body}
        CATCH_END;
        """
      else
        catch_body
      end

    suffix =
      if needs_catch? do
        """
        #{failure_cleanup}
        return Rc;
        """
      else
        ""
      end

    params = NativeFunctionCall.params(decl, module_name, decl_map)

    """
    static RC #{part_c_name}_native(ElmcValue **out, #{params}) {
      #{Enum.join(prefix, "\n  ")}
      #{core}
      #{suffix}
    }
    """
  end

  defp fused_call_args(arg_bindings, arg_kinds) do
    arg_bindings
    |> Enum.zip(arg_kinds)
    |> Enum.map_join(", ", fn {{_arg, c_arg, _index}, kind} ->
      case kind do
        :native_int -> c_arg
        :native_bool -> c_arg
        :boxed -> c_arg
      end
    end)
  end

  defp prepare_catch_body(body_text, body_var) do
    body_text =
      body_text
      |> String.replace("return #{body_var};", "")
      |> String.trim_trailing()

    if ValueSlots.owned_ref?(body_var) or RcRuntimeEmit.function_out_ref?(body_var) do
      {"", body_text}
    else
      null_decl = "ElmcValue *#{body_var} = NULL;"
      {null_decl, String.replace(body_text, null_decl, "", global: false) |> String.trim_trailing()}
    end
  end

  defp rc_body_needs_catch?(body_text) when is_binary(body_text) do
    String.contains?(body_text, "CHECK_RC") or
      String.contains?(body_text, "CHECK_RC_TO") or
      String.contains?(body_text, "\nbreak;") or
      String.contains?(body_text, "owned[")
  end

  defp peel_lets(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}) do
    {body, lets} = peel_lets(in_expr)
    {body, lets ++ [{name, value_expr}]}
  end

  defp peel_lets(expr), do: {expr, []}

  defp rebuild_lets([], body), do: body

  # peel_lets accumulates inner bindings first; reduce in that same order so the
  # first binding wraps the body and the last binding is outermost in source.
  defp rebuild_lets(lets, body) do
    Enum.reduce(lets, body, fn {name, value}, acc ->
      %{op: :let_in, name: name, value_expr: value, in_expr: acc}
    end)
  end

  defp fold_append([segment]), do: segment

  defp fold_append(segments) do
    Enum.reduce(segments, fn segment, acc ->
      %{op: :call, name: "__append__", args: [acc, segment]}
    end)
  end

  defp required_lets(all_lets, segments, arg_names) do
    bound =
      arg_names
      |> Enum.map(&EnvBindings.binding_key/1)
      |> MapSet.new()

    needed =
      Enum.reduce(segments, MapSet.new(), fn segment, acc ->
        MapSet.union(acc, free_vars(segment, bound))
      end)

    expand_required_lets(all_lets, needed, bound)
  end

  defp expand_required_lets(all_lets, needed, bound) do
    lets_by_name =
      Map.new(all_lets, fn {name, value} -> {EnvBindings.binding_key(name), {name, value}} end)

    expanded_needed =
      Enum.reduce(needed, needed, fn var, acc ->
        case Map.get(lets_by_name, var) do
          {_name, value} -> MapSet.union(acc, free_vars(value, bound))
          nil -> acc
        end
      end)

    if MapSet.equal?(expanded_needed, needed) do
      all_lets
      |> Enum.filter(fn {name, _} ->
        MapSet.member?(expanded_needed, EnvBindings.binding_key(name))
      end)
    else
      expand_required_lets(all_lets, expanded_needed, bound)
    end
  end

  defp free_vars(%{op: :var, name: name}, bound) when is_binary(name) or is_atom(name) do
    key = EnvBindings.binding_key(name)
    if MapSet.member?(bound, key), do: MapSet.new(), else: MapSet.new([key])
  end

  defp free_vars(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}, bound) do
    value_vars = free_vars(value_expr, bound)
    in_vars = free_vars(in_expr, MapSet.put(bound, EnvBindings.binding_key(name)))
    MapSet.union(value_vars, in_vars)
  end

  defp free_vars(%{op: :lambda, args: args, body: body}, bound) when is_list(args) do
    lambda_bound =
      Enum.reduce(args, bound, fn arg, acc -> MapSet.put(acc, EnvBindings.binding_key(arg)) end)

    free_vars(body, lambda_bound)
  end

  defp free_vars(%{op: :field_access, arg: arg}, bound) when is_binary(arg) or is_atom(arg) do
    key = EnvBindings.binding_key(arg)
    if MapSet.member?(bound, key), do: MapSet.new(), else: MapSet.new([key])
  end

  defp free_vars(expr, bound) when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.reduce(MapSet.new(), fn value, acc ->
      MapSet.union(acc, free_vars(value, bound))
    end)
  end

  defp free_vars(values, bound) when is_list(values) do
    Enum.reduce(values, MapSet.new(), fn value, acc ->
      MapSet.union(acc, free_vars(value, bound))
    end)
  end

  defp free_vars(_expr, _bound), do: MapSet.new()
end
