defmodule Elmx.Runtime.Values do
  @moduledoc """
  Wire-format helpers for generated Elm code and debugger execution.
  """

  alias Elmx.Runtime.Platform.Manager
  alias Elmx.Types

  @spec cmd_none() :: Types.wire_cmd()
  def cmd_none, do: Elmx.Runtime.Cmd.none()

  @spec cmd_batch([Types.wire_cmd_input()]) :: Types.wire_cmd()
  def cmd_batch(commands) when is_list(commands) do
    if manager_batch?(commands) do
      Manager.batch(Enum.map(commands, &manager_value/1))
    else
      Elmx.Runtime.Cmd.batch(commands)
    end
  end

  @spec cmd_map(term(), Types.wire_cmd_input()) :: Types.wire_cmd()
  def cmd_map(fun, cmd), do: Manager.map(fun, manager_value(cmd))

  def cmd_map(fun), do: fn cmd -> cmd_map(fun, cmd) end

  @spec sub_batch([term()]) :: term()
  def sub_batch(subs) when is_list(subs), do: Manager.batch(Enum.map(subs, &manager_value/1))

  @spec sub_map(term(), term()) :: term()
  def sub_map(fun, sub), do: Manager.map(fun, manager_value(sub))

  def sub_map(fun), do: fn sub -> sub_map(fun, sub) end

  @spec port_outgoing(String.t(), term()) :: Types.wire_cmd()
  def port_outgoing(port_key, payload) when is_binary(port_key),
    do: Manager.port(port_key, payload)

  @spec port_incoming_sub(String.t(), term()) :: term()
  def port_incoming_sub(port_key, callback) when is_binary(port_key),
    do: Manager.port(port_key, callback)

  defp manager_value(value), do: value

  defp manager_batch?(commands) when is_list(commands) do
    Enum.any?(commands, &manager_item?/1)
  end

  defp manager_item?(item) when is_map(item) do
    Map.has_key?(item, "$") or Map.has_key?(item, :"$")
  end

  defp manager_item?(item) when is_function(item), do: true
  defp manager_item?(_), do: false

  @spec ctor(String.t(), [Types.wire_input()]) :: Types.wire_ctor()
  def ctor(name, args) when is_binary(name) and is_list(args) do
    %{"ctor" => name, "args" => Enum.map(args, &wire_value/1)}
  end

  @spec field_call(Types.wire_map() | map(), String.t(), Types.registry_args()) ::
          Types.wire_value() | Types.elm_value()
  def field_call(target, field, args) when is_map(target) and is_binary(field) and is_list(args) do
    fun = Map.get(target, field) || Map.get(target, String.to_atom(field))

    cond do
      is_function(fun, length(args)) -> apply(fun, args)
      is_function(fun, 1) and args != [] -> apply(fun, args)
      true -> Map.get(target, field)
    end
  end

  @spec wire_value(Types.wire_input()) :: Types.wire_value()
  def wire_value(%{"ctor" => "True", "args" => []}), do: true
  def wire_value(%{"ctor" => "False", "args" => []}), do: false

  def wire_value(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args),
    do: %{"ctor" => ctor, "args" => Enum.map(args, &wire_value/1)}

  def wire_value(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), wire_value(v)} end)
  end

  def wire_value(list) when is_list(list), do: Enum.map(list, &wire_value/1)
  def wire_value(value) when is_boolean(value), do: value
  def wire_value(nil), do: nil

  def wire_value(value) when is_integer(value) or is_float(value) or is_binary(value), do: value
  def wire_value({ctor, args}) when is_atom(ctor) and is_list(args),
    do: %{"ctor" => Atom.to_string(ctor), "args" => Enum.map(args, &wire_value/1)}

  def wire_value(value) when is_tuple(value) do
    case Tuple.to_list(value) do
      [ctor | args] when is_atom(ctor) ->
        %{"ctor" => Atom.to_string(ctor), "args" => Enum.map(args, &wire_value/1)}

      _ ->
        value
    end
  end

  def wire_value(:True), do: true
  def wire_value(:False), do: false

  def wire_value(atom) when is_atom(atom) and atom not in [true, false] do
    %{"ctor" => Atom.to_string(atom), "args" => []}
  end

  def wire_value(value), do: value

  @spec model_to_runtime_map(map() | Types.wire_input()) :: Types.runtime_model()
  def model_to_runtime_map(model) when is_map(model) do
    wire_value(model)
  end

  def model_to_runtime_map(model), do: %{"value" => wire_value(model)}

  @spec tuple_result_to_model_cmd({map() | Types.wire_input(), Types.wire_cmd_input()} | map() | Types.wire_input()) ::
          {Types.runtime_model(), Types.wire_cmd()}
  def tuple_result_to_model_cmd({model, cmd}) when is_map(model) do
    {model_to_runtime_map(model), wire_cmd(cmd)}
  end

  def tuple_result_to_model_cmd(model) when is_map(model) do
    {model_to_runtime_map(model), cmd_none()}
  end

  def tuple_result_to_model_cmd(other) do
    {%{"result" => wire_value(other)}, cmd_none()}
  end

  @spec wire_cmd(Types.wire_cmd_input()) :: Types.wire_cmd()
  def wire_cmd(cmd) when is_map(cmd), do: cmd
  def wire_cmd(_), do: cmd_none()
end
