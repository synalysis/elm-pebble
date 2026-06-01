defmodule Elmx.Runtime.Values do
  @moduledoc """
  Wire-format helpers for generated Elm code and debugger execution.
  """

  alias Elmx.Types

  @spec cmd_none() :: Types.wire_cmd()
  def cmd_none, do: Elmx.Runtime.Cmd.none()

  @spec cmd_batch(list()) :: Types.wire_cmd()
  def cmd_batch(commands) when is_list(commands), do: Elmx.Runtime.Cmd.batch(commands)

  @spec ctor(String.t(), list()) :: Types.wire_ctor()
  def ctor(name, args) when is_binary(name) and is_list(args) do
    %{"ctor" => name, "args" => Enum.map(args, &wire_value/1)}
  end

  @spec field_call(term(), String.t(), list()) :: term()
  def field_call(target, field, args) when is_binary(field) and is_list(args) do
    fun = Map.get(target, field) || Map.get(target, String.to_atom(field))

    cond do
      is_function(fun, length(args)) -> apply(fun, args)
      is_function(fun, 1) and args != [] -> apply(fun, args)
      true -> Map.get(target, field)
    end
  end

  @spec wire_value(term()) :: Types.wire_value() | term()
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

  @spec model_to_runtime_map(term()) :: Types.runtime_model()
  def model_to_runtime_map(model) when is_map(model) do
    wire_value(model)
  end

  def model_to_runtime_map(model), do: %{"value" => wire_value(model)}

  @spec tuple_result_to_model_cmd(term()) :: {Types.runtime_model(), Types.wire_cmd()}
  def tuple_result_to_model_cmd({model, cmd}) when is_map(model) do
    {model_to_runtime_map(model), wire_cmd(cmd)}
  end

  def tuple_result_to_model_cmd(model) when is_map(model) do
    {model_to_runtime_map(model), cmd_none()}
  end

  def tuple_result_to_model_cmd(other) do
    {%{"result" => wire_value(other)}, cmd_none()}
  end

  @spec wire_cmd(term()) :: Types.wire_cmd()
  def wire_cmd(cmd) when is_map(cmd), do: cmd
  def wire_cmd(_), do: cmd_none()
end
