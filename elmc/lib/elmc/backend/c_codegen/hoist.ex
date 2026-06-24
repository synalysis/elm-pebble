defmodule Elmc.Backend.CCodegen.Hoist do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @type hoisted_native_bool_key :: term()
  @type hoisted_native_int_map :: %{hoisted_native_bool_key() => String.t()}

  @spec put_hoisted_native_bool(Types.compile_env(), Types.ir_expr(), String.t()) ::
          Types.compile_env()
  def put_hoisted_native_bool(env, expr, ref) when is_binary(ref) do
    hoisted = Map.get(env, :__hoisted_native_bools__, %{})

    hoisted =
      expr
      |> hoisted_native_bool_key_aliases(ref)
      |> Enum.reduce(hoisted, fn {key, value}, acc -> Map.put(acc, key, value) end)

    Map.put(env, :__hoisted_native_bools__, hoisted)
  end

  def put_hoisted_native_bool(env, _expr, _ref), do: env

  @spec hoisted_native_bool_ref(Types.compile_env(), Types.ir_expr()) :: String.t() | nil
  def hoisted_native_bool_ref(env, expr) do
    env
    |> Map.get(:__hoisted_native_bools__, %{})
    |> Map.get(hoisted_native_bool_key(expr))
  end

  @spec hoisted_native_bool_key(Types.ir_expr() | term()) :: hoisted_native_bool_key()
  defp hoisted_native_bool_key(%{op: :case, subject: subject} = expr) do
    {:case, Map.get(expr, :platform_static_macro), hoisted_native_bool_key(subject)}
  end

  defp hoisted_native_bool_key(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) do
    {:qualified, Host.normalize_special_target(target),
     Enum.map(args || [], &hoisted_native_bool_key/1)}
  end

  defp hoisted_native_bool_key(%{op: :call, name: name, args: args}) when is_binary(name) do
    {:call, name, Enum.map(args || [], &hoisted_native_bool_key/1)}
  end

  defp hoisted_native_bool_key(%{op: :field_access, arg: arg, field: field})
       when is_binary(field) do
    {:field, hoisted_native_bool_arg_key(arg), field}
  end

  defp hoisted_native_bool_key(%{op: :compare, kind: kind, left: left, right: right}) do
    {:compare, kind, hoisted_native_bool_key(left), hoisted_native_bool_key(right)}
  end

  defp hoisted_native_bool_key(%{op: :var, name: name}) when is_binary(name) or is_atom(name),
    do: {:var, EnvBindings.binding_key(name)}

  defp hoisted_native_bool_key(%{op: :int_literal, value: value}), do: {:int, value}
  defp hoisted_native_bool_key(%{op: :char_literal, value: value}), do: {:char, value}
  defp hoisted_native_bool_key(other) when is_map(other), do: {:other, Map.get(other, :op)}

  defp hoisted_native_bool_key(other), do: other

  @spec hoisted_native_bool_key_aliases(Types.ir_expr(), String.t()) :: [
          {hoisted_native_bool_key(), String.t()}
        ]
  defp hoisted_native_bool_key_aliases(expr, ref) do
    base = [{hoisted_native_bool_key(expr), ref}]

    case inverse_native_bool_key(expr) do
      nil -> base
      inverse_key -> [{inverse_key, inverse_ref(ref)} | base]
    end
  end

  @spec inverse_native_bool_key(Types.ir_expr()) :: hoisted_native_bool_key() | nil
  defp inverse_native_bool_key(%{op: :compare, kind: kind, left: left, right: right})
       when kind in [:eq, :neq, "eq", "neq"] do
    inverse_kind =
      case kind do
        :eq -> :neq
        "eq" -> "neq"
        :neq -> :eq
        "neq" -> "eq"
      end

    hoisted_native_bool_key(%{op: :compare, kind: inverse_kind, left: left, right: right})
  end

  defp inverse_native_bool_key(%{op: :runtime_call, function: "elmc_basics_not", args: [value]}),
    do: hoisted_native_bool_key(value)

  defp inverse_native_bool_key(%{op: :call, name: name, args: [value]})
       when name in ["not", "Basics.not"],
       do: hoisted_native_bool_key(value)

  defp inverse_native_bool_key(%{op: :qualified_call, target: target, args: [value]}) do
    if Host.normalize_special_target(target) == "Basics.not" do
      hoisted_native_bool_key(value)
    end
  end

  defp inverse_native_bool_key(_expr), do: nil

  @spec inverse_ref(String.t()) :: String.t()
  defp inverse_ref("1"), do: "0"
  defp inverse_ref("0"), do: "1"
  defp inverse_ref(ref), do: "!(" <> ref <> ")"

  @spec hoisted_native_bool_arg_key(Types.ir_expr() | String.t() | atom()) ::
          hoisted_native_bool_key()
  defp hoisted_native_bool_arg_key(name) when is_binary(name) or is_atom(name),
    do: {:var, EnvBindings.binding_key(name)}

  defp hoisted_native_bool_arg_key(%{op: :var, name: name}) when is_binary(name) or is_atom(name),
    do: {:var, EnvBindings.binding_key(name)}

  defp hoisted_native_bool_arg_key(other), do: hoisted_native_bool_key(other)

  @spec hoisted_native_ints_enabled?(Types.compile_env()) :: boolean()
  def hoisted_native_ints_enabled?(env) do
    Map.get(env, :__hoisted_native_ints_enabled__, false) or
      Process.get(:elmc_hoisted_native_ints_scope, false)
  end

  @spec hoisted_native_int_key(Types.ir_expr()) :: hoisted_native_bool_key()
  defp hoisted_native_int_key(expr),
    do: expr |> hoisted_native_int_key_raw() |> normalize_hoist_key()

  @spec hoisted_native_int_key_raw(Types.ir_expr()) :: hoisted_native_bool_key()
  defp hoisted_native_int_key_raw(%{op: :c_int_expr, value: value}) when is_binary(value),
    do: {:c_int, value}

  defp hoisted_native_int_key_raw(%{op: :call, name: name, args: args})
       when name in ["min", "max"] do
    {:minmax, name, minmax_arg_keys(args)}
  end

  defp hoisted_native_int_key_raw(%{op: :runtime_call, function: function, args: args})
       when function in ["elmc_basics_min", "elmc_basics_max"] do
    {:minmax, Host.native_min_max_name(function), minmax_arg_keys(args)}
  end

  defp hoisted_native_int_key_raw(%{op: :qualified_call, target: target, args: args})
       when target in ["Basics.min", "Basics.max"] do
    name = target |> String.split(".") |> List.last()
    {:minmax, name, minmax_arg_keys(args)}
  end

  defp hoisted_native_int_key_raw(expr), do: hoisted_native_bool_key(expr)

  @spec minmax_arg_keys([Types.ir_expr()] | Types.ir_expr() | nil) :: [hoisted_native_bool_key()]
  defp minmax_arg_keys(args) do
    args
    |> List.wrap()
    |> Enum.map(&hoisted_native_int_key/1)
    |> Enum.sort()
  end

  @spec normalize_hoist_key(hoisted_native_bool_key()) :: hoisted_native_bool_key()
  defp normalize_hoist_key({:minmax, name, keys}) when is_list(keys),
    do: {:minmax, name, Enum.sort(Enum.map(keys, &normalize_hoist_key/1))}

  defp normalize_hoist_key({:field, arg, field}),
    do: {:field, normalize_hoist_arg_key(arg), field}

  defp normalize_hoist_key({:var, name}), do: {:var, EnvBindings.binding_key(name)}

  defp normalize_hoist_key({:call, name, args}),
    do: {:call, name, Enum.map(args || [], &normalize_hoist_key/1)}

  defp normalize_hoist_key({:qualified, target, args}),
    do: {:qualified, target, Enum.map(args || [], &normalize_hoist_key/1)}

  defp normalize_hoist_key({:c_int, value}), do: {:c_int, value}

  defp normalize_hoist_key({:int, value}), do: {:int, value}
  defp normalize_hoist_key({:char, value}), do: {:char, value}
  defp normalize_hoist_key(other), do: other

  @spec normalize_hoist_arg_key(Types.ir_expr() | String.t() | atom()) :: hoisted_native_bool_key()
  defp normalize_hoist_arg_key(name) when is_binary(name) or is_atom(name),
    do: {:var, EnvBindings.binding_key(name)}

  defp normalize_hoist_arg_key(%{op: :var, name: name}), do: {:var, EnvBindings.binding_key(name)}
  defp normalize_hoist_arg_key(other), do: normalize_hoist_key(other)

  @spec register_hoisted_native_int(Types.ir_expr(), String.t()) :: :ok
  def register_hoisted_native_int(expr, ref) when is_binary(ref) do
    hoisted =
      Enum.reduce(
        hoisted_native_int_key_aliases(expr),
        Process.get(:elmc_hoisted_native_ints, %{}),
        fn
          key, acc -> Map.put(acc, key, ref)
        end
      )

    Process.put(:elmc_hoisted_native_ints, hoisted)
  end

  @spec register_hoisted_native_int_init(String.t(), String.t()) :: :ok
  def register_hoisted_native_int_init(ref, init_expr)
      when is_binary(ref) and is_binary(init_expr) do
    inits = Process.get(:elmc_hoisted_native_int_inits, %{})
    Process.put(:elmc_hoisted_native_int_inits, Map.put(inits, ref, init_expr))
    :ok
  end

  @spec stable_hoist_init?(String.t()) :: boolean()
  def stable_hoist_init?(init) when is_binary(init) do
    not Regex.match?(~r/\b(?:native_if_|native_let_|tmp_|native_case_)\d+\b/, init)
  end

  @spec hoisted_native_int_branch_preamble(map(), keyword()) :: String.t()
  def hoisted_native_int_branch_preamble(before_inits, opts \\ []) do
    allow_record_getters? = Keyword.get(opts, :allow_record_getters, false)

    Process.get(:elmc_hoisted_native_int_inits, %{})
    |> Map.drop(Map.keys(before_inits))
    |> Enum.filter(fn {_ref, init} ->
      stable_hoist_init?(init) or
        (allow_record_getters? and String.starts_with?(init, "ELMC_RECORD_GET_INDEX"))
    end)
    |> Enum.sort_by(fn {ref, _init} -> ref end)
    |> Enum.map_join("\n", fn {ref, init} -> "  const elmc_int_t #{ref} = #{init};" end)
    |> case do
      "" -> ""
      preamble -> preamble <> "\n"
    end
  end

  @spec drop_unused_native_minmax_decls(String.t()) :: String.t()
  def drop_unused_native_minmax_decls(code) when is_binary(code) do
    code
    |> String.split("\n")
    |> drop_unused_native_minmax_decl_lines()
    |> Enum.join("\n")
  end

  @spec unused_native_minmax_refs(String.t()) :: [String.t()]
  def unused_native_minmax_refs(code) when is_binary(code) do
    code
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case Regex.run(
             ~r/^\s*const elmc_int_t (native_(?:min|max)(?:_left|_right)?_\d+) = /,
             line
           ) do
        [_, ref] ->
          if native_minmax_hoist_used?(code, ref), do: [], else: [ref]

        _ ->
          []
      end
    end)
  end

  @spec drop_unused_native_minmax_decl_lines([String.t()]) :: [String.t()]
  defp drop_unused_native_minmax_decl_lines(lines) do
    case find_removable_native_minmax_line(lines) do
      nil ->
        lines

      index ->
        lines
        |> List.delete_at(index)
        |> drop_unused_native_minmax_decl_lines()
    end
  end

  @spec find_removable_native_minmax_line([String.t()]) :: non_neg_integer() | nil
  defp find_removable_native_minmax_line(lines) do
    body = Enum.join(lines, "\n")

    Enum.find_index(lines, fn line ->
      case Regex.run(
             ~r/^\s*const elmc_int_t (native_(?:min|max)(?:_left|_right)?_\d+) = /,
             line
           ) do
        [_, ref] -> not native_minmax_hoist_used?(body, ref)
        _ -> false
      end
    end)
  end

  @spec native_minmax_hoist_used?(String.t(), String.t()) :: boolean()
  defp native_minmax_hoist_used?(body, ref) when is_binary(body) and is_binary(ref) do
    Regex.scan(~r/\b#{Regex.escape(ref)}\b/, body) |> length() > 1
  end

  @spec drop_branch_only_redeclared_hoists(String.t(), String.t(), String.t()) :: String.t()
  def drop_branch_only_redeclared_hoists(preamble, then_code, else_code)
      when is_binary(preamble) and is_binary(then_code) and is_binary(else_code) do
    if preamble == "" do
      ""
    else
      preamble
      |> String.split("\n", trim: true)
      |> Enum.reject(fn line ->
        case Regex.run(~r/^const elmc_int_t (\w+) =/, String.trim(line)) do
          [_, ref] ->
            declared_in_then? = String.contains?(then_code, "const elmc_int_t #{ref} =")
            used_in_else? = hoist_ref_used?(else_code, ref)

            declared_in_then? and not used_in_else?

          _ ->
            false
        end
      end)
      |> case do
        [] -> ""
        lines -> Enum.join(lines, "\n") <> "\n"
      end
    end
  end

  @spec hoist_ref_used?(String.t(), String.t()) :: boolean()
  defp hoist_ref_used?(body, ref) do
    String.contains?(body, ref) and not String.contains?(body, "const elmc_int_t #{ref} =")
  end

  @spec hoisted_native_int_key_aliases(Types.ir_expr()) :: [hoisted_native_bool_key()]
  defp hoisted_native_int_key_aliases(expr) do
    [hoisted_native_int_key(expr) | minmax_cross_form_keys(expr)]
    |> Enum.uniq()
  end

  @spec minmax_cross_form_keys(Types.ir_expr()) :: [term()]
  defp minmax_cross_form_keys(expr) when is_map(expr) do
    case Map.get(expr, :op) do
      :call ->
        case expr do
          %{name: name, args: args} when name in ["min", "max"] ->
            [
              hoisted_native_int_key(%{
                op: :runtime_call,
                function: "elmc_basics_#{name}",
                args: args
              })
            ]

          _ ->
            []
        end

      :runtime_call ->
        case expr do
          %{function: function, args: args}
          when function in ["elmc_basics_min", "elmc_basics_max"] ->
            [
              hoisted_native_int_key(%{
                op: :call,
                name: Host.native_min_max_name(function),
                args: args
              })
            ]

          _ ->
            []
        end

      :qualified_call ->
        case expr do
          %{target: target, args: args} when target in ["Basics.min", "Basics.max"] ->
            name = target |> String.split(".") |> List.last()

            [
              hoisted_native_int_key(%{op: :call, name: name, args: args}),
              hoisted_native_int_key(%{
                op: :runtime_call,
                function: "elmc_basics_#{name}",
                args: args
              })
            ]

          _ ->
            []
        end

      _ ->
        []
    end
  end

  @spec lookup_key(Types.ir_expr()) :: term()
  def lookup_key(expr), do: hoisted_native_int_key(expr)

  @spec hoisted_native_int_lookup(Types.compile_env(), Types.ir_expr()) ::
          {:ok, String.t()} | :error
  def hoisted_native_int_lookup(env, expr) do
    if hoisted_native_ints_enabled?(env) do
      key = hoisted_native_int_key(expr)
      hoisted = hoisted_native_int_map(env)

      case Map.get(hoisted, key) do
        ref when is_binary(ref) ->
          {:ok, ref}

        _ ->
          hoisted_minmax_lookup(hoisted, expr)
      end
    else
      :error
    end
  end

  @spec hoisted_native_int_map(Types.compile_env()) :: hoisted_native_int_map()
  defp hoisted_native_int_map(env) do
    Map.merge(
      Map.get(env, :__hoisted_native_ints__, %{}),
      Process.get(:elmc_hoisted_native_ints, %{})
    )
  end

  @spec hoisted_minmax_lookup(hoisted_native_int_map(), Types.ir_expr()) ::
          {:ok, String.t()} | :error
  defp hoisted_minmax_lookup(hoisted, %{op: :call, name: name, args: args})
       when name in ["min", "max"] do
    lookup_minmax_keys(hoisted, name, minmax_arg_keys(args))
  end

  defp hoisted_minmax_lookup(hoisted, %{op: :runtime_call, function: function, args: args})
       when function in ["elmc_basics_min", "elmc_basics_max"] do
    lookup_minmax_keys(hoisted, Host.native_min_max_name(function), minmax_arg_keys(args))
  end

  defp hoisted_minmax_lookup(hoisted, %{op: :qualified_call, target: target, args: args})
       when target in ["Basics.min", "Basics.max"] do
    name = target |> String.split(".") |> List.last()
    lookup_minmax_keys(hoisted, name, minmax_arg_keys(args))
  end

  defp hoisted_minmax_lookup(_hoisted, _expr), do: :error

  @spec lookup_minmax_keys(hoisted_native_int_map(), String.t(), [hoisted_native_bool_key()]) ::
          {:ok, String.t()} | :error
  defp lookup_minmax_keys(hoisted, name, arg_keys) do
    case Map.get(hoisted, {:minmax, name, arg_keys}) do
      ref when is_binary(ref) ->
        {:ok, ref}

      _ ->
        Enum.find_value(hoisted, fn
          {{:minmax, ^name, keys}, ref} when is_list(keys) and is_binary(ref) ->
            if Enum.sort(Enum.map(keys, &normalize_hoist_key/1)) == arg_keys,
              do: {:ok, ref}

          _ ->
            nil
        end) || :error
    end
  end

  @spec merge_process_hoisted_native_ints(Types.compile_env()) :: Types.compile_env()
  def merge_process_hoisted_native_ints(env) do
    case Process.get(:elmc_hoisted_native_ints) do
      hoisted when is_map(hoisted) and map_size(hoisted) > 0 ->
        Map.put(
          env,
          :__hoisted_native_ints__,
          Map.merge(Map.get(env, :__hoisted_native_ints__, %{}), hoisted)
        )

      _ ->
        env
    end
  end

  @spec maybe_promote_hoisted_native_int(
          Types.ir_expr(),
          Types.compile_env(),
          String.t(),
          String.t(),
          Types.compile_counter()
        ) :: {String.t(), String.t(), Types.compile_counter()}
  def maybe_promote_hoisted_native_int(expr, env, code, ref, counter) do
    if hoisted_native_ints_enabled?(env) do
      case hoisted_native_int_lookup(env, expr) do
        {:ok, hoisted} ->
          {"", hoisted, counter}

        :error ->
          next = counter + 1
          hoisted = "direct_hoisted_int_#{next}"
          register_hoisted_native_int(expr, hoisted)

          if stable_hoist_init?(ref) do
            register_hoisted_native_int_init(hoisted, ref)
          end

          {code <> "  const elmc_int_t #{hoisted} = #{ref};\n", hoisted, next}
      end
    else
      {code, ref, counter}
    end
  end
end
