defmodule Elmc.Backend.CCodegen.EnvBindings do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @spec same_binding?(Types.binding_name(), Types.binding_name()) :: boolean()
  def same_binding?(left, right), do: binding_key(left) == binding_key(right)

  @spec binding_key(Types.binding_name()) :: String.t() | term()
  def binding_key(value) when is_atom(value), do: Atom.to_string(value)
  def binding_key(value) when is_binary(value), do: value
  def binding_key(%{op: :var, name: name}), do: binding_key(name)
  def binding_key(%{"op" => :var, "name" => name}), do: binding_key(name)
  def binding_key(%{"op" => "var", "name" => name}), do: binding_key(name)
  def binding_key(value), do: value

  @spec lookup_binding(Types.compile_env(), Types.binding_name()) :: term() | nil
  def lookup_binding(env, name) do
    Enum.find_value(env, fn {key, value} ->
      if same_binding?(key, name), do: value
    end)
  end

  @spec put_var_type(Types.compile_env(), Types.binding_name(), String.t()) :: Types.compile_env()
  def put_var_type(env, name, type) when is_binary(name) and is_binary(type) do
    types = Map.get(env, :__var_types__, %{})
    Map.put(env, :__var_types__, Map.put(types, binding_key(name), type))
  end

  def put_var_type(env, _name, _type), do: env

  @spec put_record_shape(Types.compile_env(), Types.binding_name(), Types.record_shape()) :: Types.compile_env()
  def put_record_shape(env, _name, nil), do: env

  def put_record_shape(env, name, fields) when is_list(fields) do
    key = binding_key(name)
    shapes = Map.get(env, :__record_shapes__, %{})
    Map.put(env, :__record_shapes__, Map.put(shapes, key, fields))
  end

  def put_record_shape(env, _name, _fields), do: env

  @spec put_boxed_int_binding(Types.compile_env(), Types.binding_name(), boolean()) :: Types.compile_env()
  def put_boxed_int_binding(env, name, true) when is_binary(name) or is_atom(name) do
    boxed_ints = Map.get(env, :__boxed_int_bindings__, MapSet.new())
    Map.put(env, :__boxed_int_bindings__, MapSet.put(boxed_ints, binding_key(name)))
  end

  def put_boxed_int_binding(env, name, _is_int) when is_binary(name) or is_atom(name) do
    boxed_ints =
      env
      |> Map.get(:__boxed_int_bindings__, MapSet.new())
      |> MapSet.delete(binding_key(name))

    Map.put(env, :__boxed_int_bindings__, boxed_ints)
  end

  def put_boxed_int_binding(env, _name, _is_int), do: env

  @spec boxed_int_binding?(Types.compile_env(), Types.binding_name()) :: boolean()
  def boxed_int_binding?(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__boxed_int_bindings__, MapSet.new())
    |> MapSet.member?(binding_key(name))
  end

  def boxed_int_binding?(_env, _name), do: false

  @spec put_boxed_bool_binding(Types.compile_env(), Types.binding_name(), boolean()) :: Types.compile_env()
  def put_boxed_bool_binding(env, name, true) when is_binary(name) or is_atom(name) do
    boxed_bools = Map.get(env, :__boxed_bool_bindings__, MapSet.new())
    Map.put(env, :__boxed_bool_bindings__, MapSet.put(boxed_bools, binding_key(name)))
  end

  def put_boxed_bool_binding(env, name, _is_bool) when is_binary(name) or is_atom(name) do
    boxed_bools =
      env
      |> Map.get(:__boxed_bool_bindings__, MapSet.new())
      |> MapSet.delete(binding_key(name))

    Map.put(env, :__boxed_bool_bindings__, boxed_bools)
  end

  def put_boxed_bool_binding(env, _name, _is_bool), do: env

  @spec boxed_bool_binding?(Types.compile_env(), Types.binding_name()) :: boolean()
  def boxed_bool_binding?(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__boxed_bool_bindings__, MapSet.new())
    |> MapSet.member?(binding_key(name))
  end

  def boxed_bool_binding?(_env, _name), do: false

  @spec put_boxed_string_binding(Types.compile_env(), Types.binding_name(), boolean()) :: Types.compile_env()
  def put_boxed_string_binding(env, name, true) when is_binary(name) or is_atom(name) do
    boxed_strings = Map.get(env, :__boxed_string_bindings__, MapSet.new())
    Map.put(env, :__boxed_string_bindings__, MapSet.put(boxed_strings, binding_key(name)))
  end

  def put_boxed_string_binding(env, name, _is_string) when is_binary(name) or is_atom(name) do
    boxed_strings =
      env
      |> Map.get(:__boxed_string_bindings__, MapSet.new())
      |> MapSet.delete(binding_key(name))

    Map.put(env, :__boxed_string_bindings__, boxed_strings)
  end

  def put_boxed_string_binding(env, _name, _is_string), do: env

  @spec boxed_string_binding?(Types.compile_env(), Types.binding_name()) :: boolean()
  def boxed_string_binding?(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__boxed_string_bindings__, MapSet.new())
    |> MapSet.member?(binding_key(name))
  end

  def boxed_string_binding?(_env, _name), do: false

  @spec put_native_int_binding(Types.compile_env(), Types.binding_name(), String.t()) :: Types.compile_env()
  def put_native_int_binding(env, name, ref)
       when (is_binary(name) or is_atom(name)) and is_binary(ref) do
    native_ints = Map.get(env, :__native_int_bindings__, %{})
    Map.put(env, :__native_int_bindings__, Map.put(native_ints, binding_key(name), ref))
  end

  def put_native_int_binding(env, _name, _ref), do: env

  @spec remove_native_int_binding(Types.compile_env(), Types.binding_name()) :: Types.compile_env()
  def remove_native_int_binding(env, name) when is_binary(name) or is_atom(name) do
    native_ints =
      env
      |> Map.get(:__native_int_bindings__, %{})
      |> Map.delete(binding_key(name))

    Map.put(env, :__native_int_bindings__, native_ints)
  end

  def remove_native_int_binding(env, _name), do: env

  @spec native_int_binding(Types.compile_env(), Types.binding_name()) :: String.t() | nil
  def native_int_binding(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__native_int_bindings__, %{})
    |> Map.get(binding_key(name))
  end

  def native_int_binding(_env, _name), do: nil

  @spec put_hybrid_loop_native_ref(Types.compile_env(), Types.binding_name(), String.t()) ::
          Types.compile_env()
  def put_hybrid_loop_native_ref(env, name, ref)
      when (is_binary(name) or is_atom(name)) and is_binary(ref) do
    hybrid_refs = Map.get(env, :__hybrid_loop_native_refs__, %{})
    Map.put(env, :__hybrid_loop_native_refs__, Map.put(hybrid_refs, binding_key(name), ref))
  end

  def put_hybrid_loop_native_ref(env, _name, _ref), do: env

  @spec remove_hybrid_loop_native_ref(Types.compile_env(), Types.binding_name()) ::
          Types.compile_env()
  def remove_hybrid_loop_native_ref(env, name) when is_binary(name) or is_atom(name) do
    hybrid_refs =
      env
      |> Map.get(:__hybrid_loop_native_refs__, %{})
      |> Map.delete(binding_key(name))

    Map.put(env, :__hybrid_loop_native_refs__, hybrid_refs)
  end

  def remove_hybrid_loop_native_ref(env, _name), do: env

  @spec hybrid_loop_native_ref(Types.compile_env(), Types.binding_name()) :: String.t() | nil
  def hybrid_loop_native_ref(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__hybrid_loop_native_refs__, %{})
    |> Map.get(binding_key(name))
  end

  def hybrid_loop_native_ref(_env, _name), do: nil

  @spec env_resolvable_binding_keys(Types.compile_env()) :: MapSet.t(String.t())
  def env_resolvable_binding_keys(env) do
    map_keys =
      env
      |> Map.keys()
      |> Enum.filter(fn
        key when is_binary(key) -> true
        _ -> false
      end)

    native_keys =
      [:__native_int_bindings__, :__native_bool_bindings__, :__native_float_bindings__]
      |> Enum.flat_map(fn key ->
        env |> Map.get(key, %{}) |> Map.keys()
      end)

    MapSet.new(map_keys ++ native_keys)
  end

  @spec capture_ref(Types.compile_env(), String.t()) :: String.t()
  def capture_ref(env, var_name) do
    cond do
      is_binary(ref = native_int_binding(env, var_name)) ->
        "elmc_new_int_take(#{ref})"

      is_binary(ref = native_bool_binding(env, var_name)) ->
        "elmc_new_bool_take(#{ref})"

      is_binary(ref = native_float_binding(env, var_name)) ->
        "elmc_new_float_take(#{ref})"

      match?({:forward_ref_slot, _}, Map.get(env, var_name)) ->
        {:forward_ref_slot, slot} = Map.get(env, var_name)
        "elmc_forward_ref_get(#{slot})"

      match?({:forward_ref, _}, Map.get(env, var_name)) ->
        {:forward_ref, ref} = Map.get(env, var_name)
        "elmc_forward_ref_capture(#{ref})"

      match?({:native_record, _}, Map.get(env, var_name)) ->
        {:native_record, fields} = Map.get(env, var_name)
        Elmc.Backend.CCodegen.FunctionCallCompile.capture_native_record(env, var_name, fields)

      Map.has_key?(env, var_name) ->
        source = Map.get(env, var_name)

        if is_binary(source), do: source, else: var_name

      true ->
        var_name
    end
  end

  @spec direct_args?(Types.compile_env()) :: boolean()
  def direct_args?(env), do: Map.get(env, :__direct_args__, false)

  @spec function_arity(Types.compile_env(), String.t(), String.t(), [Types.ir_expr()]) ::
          non_neg_integer()
  def function_arity(env, module_name, name, call_args \\ []) do
    case Map.get(effective_function_arities(env), {module_name, name}) do
      arity when is_integer(arity) -> arity
      nil -> decl_arity(env, module_name, name, call_args)
    end
  end

  @spec effective_function_arities(Types.compile_env()) :: %{
          optional({String.t(), String.t()}) => non_neg_integer()
        }
  def effective_function_arities(env) do
    case Map.get(env, :__function_arities__, %{}) do
      map when map_size(map) > 0 -> map
      _ -> Process.get(:elmc_function_arities, %{})
    end
  end

  @spec effective_program_decls(Types.compile_env()) :: Types.function_decl_map()
  def effective_program_decls(env) do
    case Map.get(env, :__program_decls__, %{}) do
      map when map_size(map) > 0 -> map
      _ -> Process.get(:elmc_program_decls, %{})
    end
  end

  @spec effective_direct_call_targets(Types.compile_env()) :: MapSet.t(Types.function_decl_key())
  def effective_direct_call_targets(env) do
    case Map.get(env, :__direct_call_targets__) do
      %MapSet{} = targets -> targets
      _ -> Process.get(:elmc_direct_call_targets, MapSet.new())
    end
  end

  @spec direct_call_target?(Types.compile_env(), String.t(), String.t()) :: boolean()
  def direct_call_target?(env, module_name, name)
      when is_binary(module_name) and is_binary(name) do
    effective_direct_call_targets(env)
    |> MapSet.member?({module_name, name})
  end

  def direct_call_target?(_env, _module_name, _name), do: false

  @spec callee_borrow_args?(Types.compile_env(), String.t(), String.t()) :: boolean()
  def callee_borrow_args?(env, module_name, name)
      when is_binary(module_name) and is_binary(name) do
    case Map.get(effective_program_decls(env), {module_name, name}) do
      %{ownership: ownership} when is_list(ownership) ->
        :borrow_arg in ownership

      _ ->
        false
    end
  end

  def callee_borrow_args?(_env, _module_name, _name), do: false

  defp decl_arity(env, module_name, name, call_args) do
    case Map.get(effective_program_decls(env), {module_name, name}) do
      %{args: args} when is_list(args) -> length(args)
      _ -> length(call_args || [])
    end
  end

  @spec borrowed_arg_ref?(Types.compile_env(), String.t()) :: boolean()
  def borrowed_arg_ref?(env, c_ref) when is_binary(c_ref) do
    env
    |> Map.get(:__borrowed_arg_refs__, MapSet.new())
    |> MapSet.member?(c_ref)
  end

  def borrowed_arg_ref?(_env, _c_ref), do: false

  @spec put_borrowed_arg_refs(
          Types.compile_env(),
          Types.function_declaration(),
          [Types.c_arg_binding()]
        ) :: Types.compile_env()
  def put_borrowed_arg_refs(env, decl, arg_bindings) do
    if :borrow_arg in List.wrap(decl.ownership) do
      refs =
        arg_bindings
        |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
        |> MapSet.new()

      Map.put(env, :__borrowed_arg_refs__, refs)
    else
      env
    end
  end

  @spec put_direct_param_refs(Types.compile_env(), [Types.c_arg_binding()]) :: Types.compile_env()
  def put_direct_param_refs(env, arg_bindings) do
    refs =
      arg_bindings
      |> Enum.map(fn {_arg, c_arg, _index} -> c_arg end)
      |> MapSet.new()

    Map.put(env, :__direct_param_refs__, refs)
  end

  @spec direct_param_ref?(Types.compile_env(), String.t()) :: boolean()
  def direct_param_ref?(env, c_ref) when is_binary(c_ref) do
    env
    |> Map.get(:__direct_param_refs__, MapSet.new())
    |> MapSet.member?(c_ref)
  end

  def direct_param_ref?(_env, _c_ref), do: false

  @spec put_list_suffix_ref(Types.compile_env(), String.t()) :: Types.compile_env()
  def put_list_suffix_ref(env, c_ref) when is_binary(c_ref) do
    suffixes = Map.get(env, :__list_suffix_refs__, MapSet.new())
    Map.put(env, :__list_suffix_refs__, MapSet.put(suffixes, c_ref))
  end

  @spec list_suffix_ref?(Types.compile_env(), String.t()) :: boolean()
  def list_suffix_ref?(env, c_ref) when is_binary(c_ref) do
    env
    |> Map.get(:__list_suffix_refs__, MapSet.new())
    |> MapSet.member?(c_ref)
  end

  @spec native_int_binding?(Types.compile_env(), Types.binding_name()) :: boolean()
  def native_int_binding?(env, name) when is_binary(name) or is_atom(name),
    do: is_binary(native_int_binding(env, name))

  def native_int_binding?(_env, _name), do: false

  @spec put_native_float_binding(Types.compile_env(), Types.binding_name(), String.t()) :: Types.compile_env()
  def put_native_float_binding(env, name, ref)
       when (is_binary(name) or is_atom(name)) and is_binary(ref) do
    native_floats = Map.get(env, :__native_float_bindings__, %{})
    Map.put(env, :__native_float_bindings__, Map.put(native_floats, binding_key(name), ref))
  end

  def put_native_float_binding(env, _name, _ref), do: env

  @spec remove_native_float_binding(Types.compile_env(), Types.binding_name()) :: Types.compile_env()
  def remove_native_float_binding(env, name) when is_binary(name) or is_atom(name) do
    native_floats =
      env
      |> Map.get(:__native_float_bindings__, %{})
      |> Map.delete(binding_key(name))

    Map.put(env, :__native_float_bindings__, native_floats)
  end

  def remove_native_float_binding(env, _name), do: env

  @spec native_float_binding(Types.compile_env(), Types.binding_name()) :: String.t() | nil
  def native_float_binding(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__native_float_bindings__, %{})
    |> Map.get(binding_key(name))
  end

  def native_float_binding(_env, _name), do: nil

  @spec put_pebble_angle_binding(Types.compile_env(), Types.binding_name(), Types.ir_expr()) :: Types.compile_env()
  def put_pebble_angle_binding(env, name, expr)
       when (is_binary(name) or is_atom(name)) and is_map(expr) do
    bindings = Map.get(env, :__pebble_angle_bindings__, %{})
    Map.put(env, :__pebble_angle_bindings__, Map.put(bindings, binding_key(name), expr))
  end

  def put_pebble_angle_binding(env, _name, _expr), do: env

  @spec pebble_angle_binding(Types.compile_env(), Types.binding_name()) :: Types.ir_expr() | nil
  def pebble_angle_binding(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__pebble_angle_bindings__, %{})
    |> Map.get(binding_key(name))
  end

  def pebble_angle_binding(_env, _name), do: nil

  @spec put_native_bool_binding(Types.compile_env(), Types.binding_name(), String.t()) :: Types.compile_env()
  def put_native_bool_binding(env, name, ref)
       when (is_binary(name) or is_atom(name)) and is_binary(ref) do
    native_bools = Map.get(env, :__native_bool_bindings__, %{})
    Map.put(env, :__native_bool_bindings__, Map.put(native_bools, binding_key(name), ref))
  end

  def put_native_bool_binding(env, _name, _ref), do: env

  @spec remove_native_bool_binding(Types.compile_env(), Types.binding_name()) :: Types.compile_env()
  def remove_native_bool_binding(env, name) when is_binary(name) or is_atom(name) do
    native_bools =
      env
      |> Map.get(:__native_bool_bindings__, %{})
      |> Map.delete(binding_key(name))

    Map.put(env, :__native_bool_bindings__, native_bools)
  end

  def remove_native_bool_binding(env, _name), do: env

  @spec native_bool_binding(Types.compile_env(), Types.binding_name()) :: String.t() | nil
  def native_bool_binding(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__native_bool_bindings__, %{})
    |> Map.get(binding_key(name))
  end

  def native_bool_binding(_env, _name), do: nil


  @spec put_native_string_binding(Types.compile_env(), Types.binding_name(), String.t()) :: Types.compile_env()
  def put_native_string_binding(env, name, ref)
       when (is_binary(name) or is_atom(name)) and is_binary(ref) do
    native_strings = Map.get(env, :__native_string_bindings__, %{})
    Map.put(env, :__native_string_bindings__, Map.put(native_strings, binding_key(name), ref))
  end

  def put_native_string_binding(env, _name, _ref), do: env

  @spec native_string_binding(Types.compile_env(), Types.binding_name()) :: String.t() | nil
  def native_string_binding(env, name) when is_binary(name) or is_atom(name) do
    env
    |> Map.get(:__native_string_bindings__, %{})
    |> Map.get(binding_key(name))
  end

  def native_string_binding(_env, _name), do: nil
end
