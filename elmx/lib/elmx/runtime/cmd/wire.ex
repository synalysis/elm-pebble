defmodule Elmx.Runtime.Cmd.Wire do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.Values
  alias Elmx.Types

  def data_log_tag_id(%{"ctor" => "Tag", "args" => [tag]}) when is_integer(tag), do: {:ok, tag}
  def data_log_tag_id(%{ctor: :Tag, args: [tag]}) when is_integer(tag), do: {:ok, tag}
  def data_log_tag_id({:Tag, tag}) when is_integer(tag), do: {:ok, tag}
  def data_log_tag_id(tag) when is_integer(tag), do: {:ok, tag}
  def data_log_tag_id(_), do: :error

  @spec normalize(Types.wire_cmd() | map()) :: Types.wire_cmd()
  def normalize(%{"kind" => _} = cmd), do: cmd
  def normalize(%{kind: kind} = cmd), do: Map.new(cmd, fn {k, v} -> {to_string(k), v} end) |> Map.put("kind", to_string(kind))
  def normalize(cmd) when is_map(cmd), do: cmd
  def normalize(_), do: Cmd.none()

  @spec message_wire(Types.elm_msg()) :: {String.t(), Types.wire_value() | Types.wire_map()}
  def message_wire(%{"ctor" => ctor, "args" => args}) when is_binary(ctor),
    do: {ctor, %{"ctor" => ctor, "args" => wire_ctor_args(args)}}

  def message_wire(tuple) when is_tuple(tuple) do
    case Tuple.to_list(tuple) do
      [ctor | args] when is_atom(ctor) ->
        name = Atom.to_string(ctor)
        {name, %{"ctor" => name, "args" => wire_ctor_args(args)}}

      _ ->
        {"Unknown", %{"ctor" => "Unknown", "args" => [Values.wire_value(tuple)]}}
    end
  end

  def message_wire(ctor) when is_atom(ctor),
    do: {Atom.to_string(ctor), %{"ctor" => Atom.to_string(ctor), "args" => []}}

  def message_wire(ctor) when is_binary(ctor),
    do: {ctor, %{"ctor" => ctor, "args" => []}}

  def message_wire(tag) when is_integer(tag),
    do: {"tag:#{tag}", %{"ctor" => "tag:#{tag}", "args" => []}}

  def message_wire(other),
    do: {"Unknown", %{"ctor" => "Unknown", "args" => [Values.wire_value(other)]}}

  @spec wire_ctor_args(list()) :: [Types.wire_value()]
  def wire_ctor_args(args) when is_list(args), do: Enum.map(args, &Values.wire_value/1)
  def wire_ctor_args(_), do: []

  @doc """
  Builds `message` + `message_value` for device/storage followups.

  Nullary callback constructors (e.g. `ClockStyle24h`) get the command payload in `args`
  so debugger steps decode to `{:ClockStyle24h, true}` instead of `:ClockStyle24h`.
  """
  @spec callback_message_value(Types.elm_msg(), Types.wire_value()) ::
          {String.t(), Types.wire_map()}
  def callback_message_value(callback, payload) do
    {message, message_value} =
      case callback do
        fun when is_function(fun, 1) and not is_nil(payload) ->
          message_wire(fun.(payload))

        fun when is_function(fun, 0) ->
          message_wire(fun.())

        other ->
          message_wire(other)
      end

    message_value =
      case message_value do
        %{"ctor" => ctor, "args" => []} when not is_nil(payload) ->
          %{"ctor" => ctor, "args" => [Values.wire_value(payload)]}

        other ->
          other
      end

    {message, message_value}
  end

end
