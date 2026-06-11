defmodule IdeWeb.WorkspaceLive.DebuggerPreview.RuntimeAccess do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: PreviewTypes

  @type runtime_input :: PreviewTypes.runtime_input()
  @type model_map :: PreviewTypes.model_map()
  @type wire_map :: PreviewTypes.wire_map()
  @type wire_value :: PreviewTypes.wire_value()
  @type view_node :: PreviewTypes.view_node()

  @spec runtime_model(runtime_input()) :: model_map()
  def runtime_model(runtime) when is_map(runtime) do
    model = runtime[:model] || runtime["model"]

    cond do
      is_map(model) and is_map(model["runtime_model"]) -> model["runtime_model"]
      is_map(model) and is_map(model[:runtime_model]) -> model[:runtime_model]
      is_map(model) -> model
      is_map(runtime[:state]) -> runtime[:state]
      is_map(runtime["state"]) -> runtime["state"]
      true -> %{}
    end
  end

  def runtime_model(_runtime), do: %{}

  @spec raw_runtime_model(runtime_input()) :: model_map()
  def raw_runtime_model(runtime) when is_map(runtime) do
    if is_map(runtime[:model]), do: runtime[:model], else: %{}
  end

  def raw_runtime_model(_runtime), do: %{}

  @spec primary_int_model_value(model_map()) :: integer() | nil
  def primary_int_model_value(model) when is_map(model) do
    Enum.find_value(model, fn {_key, value} ->
      cond do
        is_integer(value) -> value
        is_float(value) -> trunc(value)
        true -> nil
      end
    end)
  end

  def primary_int_model_value(_model), do: nil

  @spec text_label_from_node(view_node(), model_map()) :: String.t()
  def text_label_from_node(node, model \\ %{})

  def text_label_from_node(node, model) when is_map(node) and is_map(model) do
    env = %{"model" => model}

    text =
      case node_children(node) do
        [_font_node, _pos_node, label_node | _] ->
          resolve_text_label_value(label_node, env)

        _ ->
          resolve_text_label_value(node, env)
      end

    if is_binary(text) and String.trim(text) != "", do: text, else: "Label"
  end

  def text_label_from_node(_node, _model), do: "Label"

  @spec field_access_int(view_node(), model_map()) :: integer() | nil
  def field_access_int(node, model) when is_map(node) and is_map(model) do
    label = (Map.get(node, "label") || Map.get(node, :label) || "") |> to_string()

    field =
      (Map.get(node, "field") || Map.get(node, :field) ||
         label |> String.split(".") |> List.last())
      |> to_string()

    source_value =
      case node_children(node) do
        [source_node | _] ->
          resolve_raw_value(source_node, model)

        _ ->
          source_name = label |> String.split(".") |> List.first() |> to_string()

          cond do
            source_name == "model" ->
              model

            source_name != "" and source_name != field ->
              map_value_by_key(model, source_name)

            true ->
              nil
          end
      end

    value =
      case source_value do
        map when is_map(map) -> map_value_by_key(map, field)
        other -> other
      end

    case value do
      n when is_integer(n) -> n
      n when is_float(n) -> trunc(n)
      _ -> nil
    end
  end

  def field_access_int(_node, _model), do: nil

  @spec resolve_text_label_value(view_node(), wire_map()) :: String.t() | nil
  defp resolve_text_label_value(node, env) when is_map(node) and is_map(env) do
    value = Map.get(node, "value") || Map.get(node, :value)
    op = (Map.get(node, "op") || Map.get(node, :op) || "") |> to_string()
    type = (Map.get(node, "type") || Map.get(node, :type) || "") |> to_string()
    label = (Map.get(node, "label") || Map.get(node, :label) || "") |> to_string()

    target =
      to_string(Map.get(node, "qualified_target") || Map.get(node, :qualified_target) || "")

    cond do
      label == "__append__" ->
        values = node_children(node) |> Enum.map(&resolve_text_label_value(&1, env))

        if values != [] and Enum.all?(values, &is_binary/1) do
          Enum.join(values, "")
        end

      string_from_int_node?(node) ->
        node_children(node)
        |> List.first()
        |> resolve_raw_value(env)
        |> normalize_text_value()

      normalize_text_value(value) != nil ->
        normalize_text_value(value)

      type == "WaitingForCompanion" or
          String.ends_with?(target, "WaitingForCompanion") ->
        "Waiting for companion app"

      op == "field_access" ->
        resolve_field_access_text(node, env)

      type == "var" and label != "" ->
        env
        |> map_value_by_key(label)
        |> normalize_text_value()

      true ->
        node_children(node)
        |> Enum.find_value(&resolve_text_label_value(&1, env))
    end
  end

  defp resolve_text_label_value(_node, _env), do: nil

  @spec string_from_int_node?(view_node()) :: boolean()
  defp string_from_int_node?(node) when is_map(node) do
    target =
      to_string(Map.get(node, "qualified_target") || Map.get(node, :qualified_target) || "")

    type = to_string(Map.get(node, "type") || Map.get(node, :type) || "")

    target in ["String.fromInt", "Basics.String.fromInt"] or type == "fromInt"
  end

  @spec resolve_field_access_text(view_node(), wire_map()) :: String.t() | nil
  defp resolve_field_access_text(node, env) when is_map(node) and is_map(env) do
    label = (Map.get(node, "label") || Map.get(node, :label) || "") |> to_string()

    field =
      (Map.get(node, "field") || Map.get(node, :field) ||
         label |> String.split(".") |> List.last())
      |> to_string()

    source_value =
      case node_children(node) do
        [source_node | _] ->
          resolve_raw_value(source_node, env)

        _ ->
          if String.contains?(label, ".") do
            source_name = label |> String.split(".") |> List.first()
            map_value_by_key(env, source_name)
          else
            nil
          end
      end

    source_value
    |> case do
      map when is_map(map) -> map_value_by_key(map, field)
      _ -> nil
    end
    |> normalize_text_value()
  end

  defp resolve_field_access_text(_node, _env), do: nil

  @spec resolve_raw_value(view_node(), wire_map()) :: wire_value()
  defp resolve_raw_value(node, env) when is_map(node) and is_map(env) do
    value = Map.get(node, "value") || Map.get(node, :value)
    type = (Map.get(node, "type") || Map.get(node, :type) || "") |> to_string()
    label = (Map.get(node, "label") || Map.get(node, :label) || "") |> to_string()
    op = (Map.get(node, "op") || Map.get(node, :op) || "") |> to_string()

    cond do
      not is_nil(value) ->
        value

      op == "field_access" ->
        resolve_field_access_text(node, env)

      type == "var" and label != "" ->
        map_value_by_key(env, label)

      true ->
        nil
    end
  end

  defp resolve_raw_value(_node, _env), do: nil

  @spec normalize_text_value(wire_value()) :: String.t() | nil
  defp normalize_text_value(value) when is_binary(value) do
    if String.trim(value) != "", do: value, else: nil
  end

  defp normalize_text_value(value) when is_integer(value), do: Integer.to_string(value)

  defp normalize_text_value(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact])

  defp normalize_text_value(_value), do: nil

  @spec map_value_by_key(wire_map(), String.t()) :: wire_value()
  defp map_value_by_key(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) ||
      Enum.find_value(map, fn
        {atom_key, value} when is_atom(atom_key) ->
          if Atom.to_string(atom_key) == key, do: value, else: nil

        _ ->
          nil
      end)
  end

  @spec node_children(view_node()) :: [view_node()]
  defp node_children(node) when is_map(node) do
    case Map.get(node, "children") || Map.get(node, :children) do
      list when is_list(list) ->
        Enum.filter(list, &is_map/1)

      _ ->
        []
    end
  end
end
