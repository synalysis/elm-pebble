defmodule Elmc.Backend.CCodegen.SpawnTileChain do
  @moduledoc """
  Fuses chained `spawnTileWithSeed` on a static empty board into one buffer + two inline spawns.

  Matches `initialBoard`-shaped IR: spawn on a zero-arg board, then spawn on the first result.
  """

  alias Elmc.Backend.CCodegen.{
    FusionSupport,
    ImmortalStaticList,
    SpawnTileInline,
    Util
  }

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()]} | {:ok, String.t(), [FusionSupport.callee_key()], :rc_native} | :error
  def try_emit(_module_name, _name, nil, _decl_map), do: :error

  def try_emit(module_name, name, expr, decl_map) do
    env = %{__program_decls__: decl_map, __module__: module_name}

    with {:ok, spawn_fn, seed_param, board_expr, count} <- parse_chain(expr, decl_map, module_name, env),
         true <- tuple_pair_return?(decl_map, module_name, name),
         code when is_binary(code) <- emit(module_name, name, spawn_fn, seed_param, board_expr, count, decl_map) do
      FusionSupport.ok_rc(code, [{module_name, spawn_fn}])
    else
      _ -> :error
    end
  end

  defp tuple_pair_return?(decl_map, module_name, name) do
    case Map.get(decl_map, {module_name, name}) do
      %{type: type} when is_binary(type) ->
        type
        |> String.replace(" ", "")
        |> String.split("->")
        |> List.last()
        |> case do
          "(ListInt,Int)" <> _ -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp parse_chain(expr, decl_map, module_name, env) do
    {bindings, body} = flatten_lets(expr)
    env = Map.merge(env, %{__program_decls__: decl_map, __module__: module_name})

    with {:ok, spawn_fn, first_spawn, tuple_bind} <- find_first_spawn(bindings, module_name),
         {:ok, cells_bind, seed_bind} <- find_tuple_destructure(bindings, tuple_bind),
         {:ok, seed_param} <- seed_param_name(first_spawn),
         {:ok, board_expr} <- board_expr_from_spawn(first_spawn),
         {:ok, count} <- ImmortalStaticList.static_length(board_expr, env),
         :ok <- parse_second_spawn(body, spawn_fn, seed_bind, cells_bind, module_name) do
      {:ok, spawn_fn, seed_param, board_expr, count}
    end
  end

  defp flatten_lets(expr, acc \\ [])

  defp flatten_lets(%{op: :let_in, name: name, value_expr: value, in_expr: body}, acc)
       when is_binary(name) do
    flatten_lets(body, [{name, value} | acc])
  end

  defp flatten_lets(expr, acc), do: {Enum.reverse(acc), expr}

  defp find_first_spawn(bindings, module_name) do
    Enum.find_value(bindings, :error, fn {name, value} ->
      case parse_spawn_call(value, module_name) do
        {:ok, spawn_fn, _seed, _cells} -> {:ok, spawn_fn, value, name}
        _ -> nil
      end
    end)
  end

  defp find_tuple_destructure(bindings, tuple_bind) when is_binary(tuple_bind) do
    cells_bind =
      Enum.find_value(bindings, fn {name, value} ->
        case value do
          %{op: :tuple_first_expr, arg: %{op: :var, name: ^tuple_bind}} -> name
          _ -> nil
        end
      end)

    seed_bind =
      Enum.find_value(bindings, fn {name, value} ->
        case value do
          %{op: :tuple_second_expr, arg: %{op: :var, name: ^tuple_bind}} -> name
          _ -> nil
        end
      end)

    if is_binary(cells_bind) and is_binary(seed_bind) do
      {:ok, cells_bind, seed_bind}
    else
      :error
    end
  end

  defp parse_second_spawn(body, spawn_fn, seed_bind, cells_bind, module_name) do
    case parse_spawn_call(body, module_name) do
      {:ok, ^spawn_fn, second_seed, second_cells} ->
        if var_ref?(second_seed, seed_bind) and var_ref?(second_cells, cells_bind) do
          :ok
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp var_ref?(%{op: :var, name: name}, bind), do: name == bind
  defp var_ref?(name, bind) when is_binary(name), do: name == bind
  defp var_ref?(_, _), do: false

  defp parse_spawn_call(%{op: :qualified_call, target: target, args: args}, module_name) do
    with [seed, cells] <- args || [],
         true <- is_binary(FusionSupport.local_name(target)) do
      {:ok, FusionSupport.local_name(target), seed, cells}
    end
  end

  defp parse_spawn_call(%{op: :call, name: name, args: args}, module_name) when is_binary(name) do
    with [seed, cells] <- args || [] do
      {:ok, name, seed, cells}
    end
  end

  defp parse_spawn_call(_, _), do: :error

  defp seed_param_name(%{op: :qualified_call, args: [seed, _]}) do
    case seed do
      %{op: :var, name: name} when is_binary(name) -> {:ok, name}
      name when is_binary(name) -> {:ok, name}
      _ -> :error
    end
  end

  defp seed_param_name(%{op: :call, args: [seed, _]}) do
    case seed do
      %{op: :var, name: name} when is_binary(name) -> {:ok, name}
      _ -> :error
    end
  end

  defp seed_param_name(_), do: :error

  defp board_expr_from_spawn(%{op: :qualified_call, args: [_, board]}), do: {:ok, board}
  defp board_expr_from_spawn(%{op: :call, args: [_, board]}), do: {:ok, board}
  defp board_expr_from_spawn(_), do: :error

  defp emit(module_name, name, _spawn_fn, seed_param, board_expr, count, decl_map) do
    c_prefix = Util.module_fn_name(module_name, name)
    board_load = emit_board_load(board_expr, count, decl_map, module_name)

    """
    static RC #{c_prefix}_native(ElmcValue **out, ElmcValue *#{seed_param}) {
      RC Rc = RC_SUCCESS;
      CATCH_BEGIN
        elmc_int_t buf[#{count}];
        #{board_load}
        elmc_int_t seed_work = elmc_as_int(#{seed_param});
        #{SpawnTileInline.emit("spawn_a", "buf", count, "seed_work")}
        seed_work = spawn_a_after_tile;
        #{SpawnTileInline.emit("spawn_b", "buf", count, "seed_work")}
        ElmcValue *cells_out = NULL;
        if (elmc_list_from_int_array(&cells_out, buf, #{count}) != RC_SUCCESS)
          cells_out = elmc_list_nil();
        ElmcValue *seed_out = NULL;
        Rc = elmc_new_int(&seed_out, spawn_b_after_tile);
        CHECK_RC(Rc);
        ElmcValue *pair = NULL;
        Rc = elmc_tuple2_take(&pair, cells_out, seed_out);
        CHECK_RC(Rc);
        *out = pair;
      CATCH_END;
      return Rc;
    }
    """
  end

  defp emit_board_load(board_expr, count, _decl_map, module_name) do
    case board_expr do
      %{op: :var, name: name} when is_binary(name) ->
        """
        for (elmc_int_t i = 0; i < #{count}; i++) {
          buf[i] = 0;
        }
        """

      %{op: :qualified_call, target: target, args: []} ->
        fn_name = FusionSupport.local_name(target)
        c_fn = Util.module_fn_name(module_name, fn_name)

        """
        ElmcValue *board_src = NULL;
        if (#{c_fn}(&board_src) != RC_SUCCESS) board_src = elmc_list_nil();
        for (elmc_int_t i = 0; i < #{count}; i++) {
          buf[i] = elmc_list_nth_int_default(board_src, i, 0);
        }
        elmc_release(board_src);
        """

      %{op: :call, name: name, args: []} when is_binary(name) ->
        c_fn = Util.module_fn_name(module_name, name)

        """
        ElmcValue *board_src = NULL;
        if (#{c_fn}(&board_src) != RC_SUCCESS) board_src = elmc_list_nil();
        for (elmc_int_t i = 0; i < #{count}; i++) {
          buf[i] = elmc_list_nth_int_default(board_src, i, 0);
        }
        elmc_release(board_src);
        """

      _ ->
        """
        for (elmc_int_t i = 0; i < #{count}; i++) {
          buf[i] = 0;
        }
        """
    end
  end
end
