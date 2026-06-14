defmodule Elmc.Backend.Pebble.Types.FeatureFlags.MapType do
  @moduledoc false

  @doc false
  defmacro def_flags_type(name, keys_ast) do
    keys = keys_list!(keys_ast, __CALLER__)

    entries =
      Enum.map(keys, fn key ->
        quote(do: {required(unquote(key)), feature_flag()})
      end)

    quote do
      @type unquote(name) :: %{unquote_splicing(entries)}
    end
  end

  defp keys_list!({{:., _, [module_ast, fun]}, _, []}, caller)
       when is_atom(fun) do
    module = module_ast |> Macro.expand(caller)

    case apply(module, fun, []) do
      list when is_list(list) -> list
      other -> raise_keys_error!(other)
    end
  end

  defp keys_list!(keys_ast, _caller) do
    raise ArgumentError,
          "def_flags_type expects Keys.subset_keys/0, got: #{Macro.to_string(keys_ast)}"
  end

  defp raise_keys_error!(other) do
    raise ArgumentError, "def_flags_type expected a key list, got: #{inspect(other)}"
  end
end
