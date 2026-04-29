defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.Dict do
  @moduledoc false

  alias ElmExecutor.Runtime.CoreIREvaluator.Value.Dict, as: DictValue
  alias ElmExecutor.Runtime.CoreIREvaluator.Value.MaybeResult

  @spec eval(String.t(), term()) :: {:ok, term()} | :no_builtin
  def eval("fromlist", [pairs]) when is_list(pairs),
    do: {:ok, DictValue.dict_from_pair_list(pairs)}

  def eval("tolist", [dict]) when is_map(dict), do: {:ok, DictValue.dict_to_list(dict)}

  def eval("get", [key, dict]) when is_map(dict),
    do: {:ok, MaybeResult.maybe_map_get_ctor(dict, key)}

  def eval("insert", [key, value, dict]) when is_map(dict), do: {:ok, Map.put(dict, key, value)}
  def eval(_function_name, _values), do: :no_builtin
end
