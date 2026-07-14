defmodule Elmc.Backend.Wasm.ImportSignatures do
  @moduledoc false

  alias Elmc.Backend.Wasm.Types, as: WasmTypes

  @core_arities %{
    "runtime.retain" => 1,
    "runtime.release" => 1,
    "runtime.release_unless_reachable" => 2,
    "runtime.release_unless_reachable_from_roots" => 3,
    "runtime.release_array_lifo" => 2,
    "runtime.as_int" => 1,
    "runtime.as_bool" => 1,
    "runtime.union_tag_as_int" => 1
  }

  @builtin_defaults %{
    list_from_int_array: 3,
    list_from_values: 3,
    make_closure: 4,
    call_closure: 4,
    new_int: 2,
    new_bool: 2,
    new_float: 2,
    new_string: 2,
    list_nil: 1,
    maybe_nothing: 1,
    array_empty: 1,
    dict_empty: 1,
    set_empty: 1,
    int_zero: 1,
    unit: 1,
    release: 1,
    retain: 1,
    maybe_just_payload: 2
  }

  @spec param_count(String.t()) :: non_neg_integer()
  def param_count(import_name) when is_binary(import_name) do
    Map.get(@core_arities, import_name) || builtin_import_param_count(import_name)
  end

  @spec param_count(String.t(), non_neg_integer()) :: non_neg_integer()
  def param_count(import_name, observed_arity) when is_binary(import_name) and is_integer(observed_arity) do
    minimum =
      case Map.get(@core_arities, import_name) do
        core when is_integer(core) ->
          core

        nil ->
          builtin_default_arity(import_name)
      end

    case minimum do
      min when is_integer(min) -> max(min, observed_arity)
      nil -> observed_arity
    end
  end

  @spec call_runtime_param_count(atom(), map()) :: non_neg_integer()
  def call_runtime_param_count(:call_closure, args_map) when is_map(args_map) do
    reg_args = Map.get(args_map, :args, []) |> List.wrap() |> length()
    observed = 2 + reg_args

    case Map.get(@builtin_defaults, :call_closure) do
      nil -> observed
      fixed -> max(fixed, observed)
    end
  end

  def call_runtime_param_count(builtin, args_map) when is_atom(builtin) and is_map(args_map) do
    reg_args = Map.get(args_map, :args, []) |> List.wrap() |> length()
    literal_extra = if Map.get(args_map, :literal) != nil or Map.get(args_map, :c_expr) != nil, do: 1, else: 0
    observed = 1 + reg_args + literal_extra

    case Map.get(@builtin_defaults, builtin) do
      nil -> observed
      fixed -> max(fixed, observed)
    end
  end

  @spec value_import_type_sexpr(String.t(), non_neg_integer()) :: String.t()
  def value_import_type_sexpr(import_name, param_count) do
    params = Enum.map_join(1..param_count//1, " ", fn _ -> "i32" end)
    "(func #{WasmTypes.import_ident(import_name)} (param #{params}) (result i32))"
  end

  @spec import_type_sexpr(String.t(), non_neg_integer()) :: String.t()
  def import_type_sexpr(import_name, param_count) do
    params = Enum.map_join(1..param_count//1, " ", fn _ -> "i32" end)
    "(func #{WasmTypes.import_ident(import_name)} (param #{params}) (result i32))"
  end

  @spec function_result_sexpr() :: String.t()
  def function_result_sexpr, do: "(result i32 i32)"

  defp builtin_import_param_count("runtime." <> suffix) do
    case builtin_default_arity("runtime." <> suffix) do
      arity when is_integer(arity) -> arity
      nil -> 2
    end
  end

  defp builtin_import_param_count(_), do: 2

  defp builtin_default_arity("runtime." <> suffix) do
    suffix
    |> String.replace(".", "_")
    |> then(fn name ->
      case safe_atom(name) do
        {:ok, atom} -> Map.get(@builtin_defaults, atom)
        :error -> nil
      end
    end)
  end

  defp safe_atom(name) do
    atom = String.to_existing_atom(name)
    {:ok, atom}
  rescue
    ArgumentError -> :error
  end
end
