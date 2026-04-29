defmodule ElmExecutor.Runtime.CoreIREvaluator.Builtins.JsonDecode do
  @moduledoc false

  @spec eval(String.t(), term(), map()) :: {:ok, term()} | :no_builtin | {:error, term()}
  def eval("bool", [], ops), do: ops.kernel.("decodebool", [])
  def eval("int", [], ops), do: ops.kernel.("decodeint", [])
  def eval("float", [], ops), do: ops.kernel.("decodefloat", [])
  def eval("string", [], ops), do: ops.kernel.("decodestring", [])
  def eval("value", [], ops), do: ops.kernel.("decodevalue", [])
  def eval("field", values, ops), do: ops.kernel.("decodefield", values)
  def eval("index", values, ops), do: ops.kernel.("decodeindex", values)
  def eval("list", values, ops), do: ops.kernel.("decodelist", values)
  def eval("array", values, ops), do: ops.kernel.("decodearray", values)
  def eval("keyvaluepairs", values, ops), do: ops.kernel.("decodekeyvaluepairs", values)
  def eval("oneof", values, ops), do: ops.kernel.("oneof", values)
  def eval("succeed", values, ops), do: ops.kernel.("succeed", values)
  def eval("fail", values, ops), do: ops.kernel.("fail", values)
  def eval("null", values, ops), do: ops.kernel.("decodenull", values)
  def eval("andthen", values, ops), do: ops.kernel.("andthen", values)
  def eval("map", values, ops), do: ops.kernel.("map1", values)
  def eval("map2", values, ops), do: ops.kernel.("map2", values)
  def eval("map3", values, ops), do: ops.kernel.("map3", values)
  def eval("map4", values, ops), do: ops.kernel.("map4", values)
  def eval("map5", values, ops), do: ops.kernel.("map5", values)
  def eval("map6", values, ops), do: ops.kernel.("map6", values)
  def eval("map7", values, ops), do: ops.kernel.("map7", values)
  def eval("map8", values, ops), do: ops.kernel.("map8", values)

  def eval("decodestring", [decoder, source], ops),
    do: ops.kernel.("runonstring", [decoder, source])

  def eval("decodevalue", [decoder, value], ops), do: ops.kernel.("run", [decoder, value])
  def eval(_function_name, _values, _ops), do: :no_builtin
end
