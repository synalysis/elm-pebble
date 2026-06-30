defmodule Elmc.Backend.CCodegen.HelperParams do
  @moduledoc false

  alias Elmc.Backend.CCodegen.EnvBindings
  alias Elmc.Backend.CCodegen.Types

  @type param_spec :: {:native_int, String.t()} | {:native_bool, String.t()} | {:boxed, String.t()}

  @spec resolve(Types.compile_env(), String.t()) :: {:ok, param_spec()} | :skip | :error
  def resolve(env, var) when is_binary(var) do
    key = EnvBindings.binding_key(var)

    cond do
      is_binary(ref = EnvBindings.native_int_binding(env, key)) and c_identifier?(ref) ->
        {:ok, {:native_int, ref}}

      is_binary(ref = EnvBindings.native_bool_binding(env, key)) and c_identifier?(ref) ->
        {:ok, {:native_bool, ref}}

      is_binary(c_ref = Map.get(env, key)) and c_identifier?(c_ref) ->
        {:ok, {:boxed, c_ref}}

      zero_arg_function_var?(env, key) ->
        :skip

      true ->
        :error
    end
  end

  @spec collect([String.t()], Types.compile_env()) :: {:ok, [{String.t(), param_spec()}]} | :error
  def collect(vars, env) when is_list(vars) do
    vars
    |> Enum.sort()
    |> Enum.reduce_while([], fn var, acc ->
      case resolve(env, var) do
        {:ok, spec} -> {:cont, [{var, spec} | acc]}
        :skip -> {:cont, acc}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      params -> {:ok, params |> Enum.reverse() |> Enum.uniq_by(fn {_var, spec} -> spec end)}
    end
  end

  @spec vars_in_c_source(String.t(), Types.compile_env()) :: [String.t()]
  def vars_in_c_source(code, env) when is_binary(code) do
    env
    |> Map.keys()
    |> Enum.filter(&(is_binary(&1) and not String.starts_with?(&1, "__")))
    |> Enum.filter(fn var ->
      case resolve(env, var) do
        {:ok, spec} -> c_ref_in_source?(spec, code)
        _ -> false
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec param_decls([{String.t(), param_spec()}]) :: String.t()
  def param_decls(params) do
    params
    |> Enum.map_join(", ", fn
      {_var, {:native_int, c_ref}} -> "const elmc_int_t #{c_ref}"
      {_var, {:native_bool, c_ref}} -> "const elmc_int_t #{c_ref}"
      {_var, {:boxed, c_ref}} -> "ElmcValue *#{c_ref}"
    end)
  end

  @spec unused_param_casts([{String.t(), param_spec()}], String.t()) :: String.t()
  def unused_param_casts(params, body_text) when is_binary(body_text) do
    params
    |> Enum.map(fn {_var, spec} -> param_c_ref(spec) end)
    |> Enum.reject(fn ref -> c_ref_in_source?(ref, body_text) end)
    |> case do
      [] -> ""
      refs -> Enum.map_join(refs, "\n", &"(void)#{&1};")
    end
  end

  @spec call_args([{String.t(), param_spec()}]) :: String.t()
  def call_args(params) do
    params
    |> Enum.map_join(", ", fn {_var, spec} ->
      case spec do
        {:native_int, c_ref} -> c_ref
        {:native_bool, c_ref} -> c_ref
        {:boxed, c_ref} -> c_ref
      end
    end)
  end

  defp c_identifier?(value) when is_binary(value),
    do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, value)

  defp param_c_ref({:native_int, ref}), do: ref
  defp param_c_ref({:native_bool, ref}), do: ref
  defp param_c_ref({:boxed, ref}), do: ref

  defp c_ref_in_source?({:native_int, ref}, code), do: c_ref_in_source?(ref, code)
  defp c_ref_in_source?({:native_bool, ref}, code), do: c_ref_in_source?(ref, code)
  defp c_ref_in_source?({:boxed, ref}, code), do: c_ref_in_source?(ref, code)

  defp c_ref_in_source?(ref, code) when is_binary(ref) and is_binary(code) do
    Regex.match?(~r/\b#{Regex.escape(ref)}\b/, code)
  end

  defp zero_arg_function_var?(env, var) do
    module_name = Map.get(env, :__module__, "Main")

    case Map.get(env, :__program_decls__, %{}) do
      %{} = decl_map ->
        case Map.get(decl_map, {module_name, var}) do
          %{args: args} when args in [[], nil] -> true
          _ -> false
        end

      _ ->
        false
    end
  end
end
