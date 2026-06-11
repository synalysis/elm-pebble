defmodule IdeWeb.WorkspaceLive.DebuggerPage.ModelTree do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type model_node :: SupportTypes.wire_map()
  @type model_value :: map() | list() | String.t() | number() | boolean() | nil

  @spec debugger_model_children(model_node()) :: [%{label: String.t(), value: model_value()}]
  def debugger_model_children(value) when is_map(value) do
    if debugger_model_elm_constructor?(value) do
      []
    else
      value
      |> Enum.map(fn {key, child_value} -> %{label: to_string(key), value: child_value} end)
      |> Enum.sort_by(& &1.label)
    end
  end

  def debugger_model_children(value) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.map(fn {child_value, index} -> %{label: "[#{index}]", value: child_value} end)
  end

  def debugger_model_children(_value), do: []

  @spec debugger_model_tooltip(String.t(), model_node(), [map()], String.t()) :: String.t()
  def debugger_model_tooltip(label, _value, [], scalar)
      when is_binary(label) and is_binary(scalar),
      do: "#{label} = #{scalar}"

  def debugger_model_tooltip(label, value, _children, _scalar) when is_binary(label) do
    "#{label} #{debugger_model_container_label(value)}"
  end

  @spec debugger_model_scalar(model_node()) :: String.t()
  def debugger_model_scalar(value) when is_map(value) do
    if debugger_model_elm_constructor?(value),
      do: debugger_model_elm_value(value),
      else: inspect(value)
  end

  def debugger_model_scalar(nil), do: "null"
  def debugger_model_scalar(value) when is_binary(value), do: inspect(value)

  def debugger_model_scalar(value) when is_boolean(value),
    do: if(value, do: "True", else: "False")

  def debugger_model_scalar(value) when is_number(value), do: to_string(value)
  def debugger_model_scalar(value) when is_atom(value), do: Atom.to_string(value)
  def debugger_model_scalar(value), do: inspect(value)

  @spec debugger_model_container_label(map() | list()) :: String.t()
  def debugger_model_container_label(value) when is_map(value) do
    if debugger_model_elm_constructor?(value),
      do: debugger_model_elm_value(value),
      else: "{#{map_size(value)}}"
  end

  def debugger_model_container_label(value) when is_list(value), do: "[#{length(value)}]"

  @spec debugger_model_elm_constructor?(map()) :: boolean()
  def debugger_model_elm_constructor?(value) when is_map(value) do
    ctor = Map.get(value, "ctor") || Map.get(value, "$ctor") || Map.get(value, :ctor)
    args = Map.get(value, "args") || Map.get(value, "$args") || Map.get(value, :args) || []

    is_binary(ctor) and is_list(args) and
      value
      |> Map.keys()
      |> Enum.all?(&(to_string(&1) in ["ctor", "args", "$ctor", "$args"]))
  end

  @spec debugger_model_elm_value(map()) :: String.t()
  def debugger_model_elm_value(%{} = value) do
    ctor = Map.get(value, "ctor") || Map.get(value, "$ctor") || Map.get(value, :ctor)
    args = Map.get(value, "args") || Map.get(value, "$args") || Map.get(value, :args) || []

    case {ctor, args} do
      {ctor, []} when is_binary(ctor) ->
        ctor

      {ctor, args} when is_binary(ctor) and is_list(args) ->
        rendered_args =
          args
          |> Enum.map(&debugger_model_elm_arg_value/1)
          |> Enum.join(" ")

        String.trim("#{ctor} #{rendered_args}")

      _ ->
        inspect(value)
    end
  end

  @spec debugger_model_elm_arg_value(map()) :: String.t()
  def debugger_model_elm_arg_value(%{} = value) do
    if debugger_model_elm_constructor?(value) do
      rendered = debugger_model_elm_value(value)

      if constructor_arg_count(value) > 0 do
        "(" <> rendered <> ")"
      else
        rendered
      end
    else
      debugger_model_elm_record_value(value)
    end
  end

  def debugger_model_elm_arg_value(value) when is_list(value) do
    inner =
      value
      |> Enum.map(&debugger_model_elm_arg_value/1)
      |> Enum.join(", ")

    "[" <> inner <> "]"
  end

  def debugger_model_elm_arg_value(value) when is_boolean(value),
    do: if(value, do: "True", else: "False")

  def debugger_model_elm_arg_value(value), do: debugger_model_scalar(value)

  @spec debugger_model_elm_record_value(map()) :: String.t()
  def debugger_model_elm_record_value(value) when is_map(value) do
    inner =
      value
      |> Enum.map(fn {key, child_value} ->
        "#{key} = #{debugger_model_elm_arg_value(child_value)}"
      end)
      |> Enum.sort()
      |> Enum.join(", ")

    "{ " <> inner <> " }"
  end

  @spec constructor_arg_count(map()) :: non_neg_integer()
  def constructor_arg_count(%{} = value) do
    args = Map.get(value, "args") || Map.get(value, "$args") || Map.get(value, :args) || []
    if is_list(args), do: length(args), else: 0
  end
end
