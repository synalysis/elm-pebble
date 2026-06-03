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

  @spec put_var_type(Types.compile_env(), Types.binding_name(), String.t()) :: Types.compile_env()
  def put_var_type(env, name, type) when is_binary(name) and is_binary(type) do
    types = Map.get(env, :__var_types__, %{})
    Map.put(env, :__var_types__, Map.put(types, binding_key(name), type))
  end

  def put_var_type(env, _name, _type), do: env

  @spec put_record_shape(Types.compile_env(), Types.binding_name(), Types.record_shape()) :: Types.compile_env()
  def put_record_shape(env, _name, nil), do: env

  def put_record_shape(env, name, fields) when is_binary(name) and is_list(fields) do
    shapes = Map.get(env, :__record_shapes__, %{})
    Map.put(env, :__record_shapes__, Map.put(shapes, name, fields))
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
        "elmc_new_int(#{ref})"

      is_binary(ref = native_bool_binding(env, var_name)) ->
        "elmc_new_bool(#{ref})"

      is_binary(ref = native_float_binding(env, var_name)) ->
        "elmc_new_float(#{ref})"

      match?({:forward_ref, _}, Map.get(env, var_name)) ->
        {:forward_ref, ref} = Map.get(env, var_name)
        "elmc_forward_ref_capture(#{ref})"

      match?({:native_record, _}, Map.get(env, var_name)) ->
        {:native_record, fields} = Map.get(env, var_name)
        Elmc.Backend.CCodegen.FunctionCallCompile.capture_native_record(env, var_name, fields)

      Map.has_key?(env, var_name) ->
        source = Map.get(env, var_name)

        if is_binary(source) do
          "elmc_retain(#{source})"
        else
          var_name
        end

      true ->
        var_name
    end
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
