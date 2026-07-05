defmodule Ide.Test.TemplateElmxElmcParity.ElmcRunner.PayloadCodegen do
  @moduledoc false

  alias Ide.Test.TemplateElmxElmcParity.ExecutionPlan.TimelineMessageValue

  @phone_to_watch_tags %{
    "ProvideWeather" => 1,
    "ProvideEnvironment" => 2,
    "RequestWeatherEnv" => 1,
    "ProvideFigure" => 1,
    "BeginFigure" => 2,
    "ProvidePiece" => 3,
    "EndFigure" => 4
  }

  @weather_condition_tags %{
    "Clear" => 1,
    "Cloudy" => 2,
    "Fog" => 3,
    "Drizzle" => 4,
    "Rain" => 5,
    "Snow" => 6,
    "Showers" => 7,
    "Storm" => 8,
    "UnknownWeather" => 9
  }

  @nullary_union_tags %{
    "Monday" => 0,
    "Tuesday" => 1,
    "Wednesday" => 2,
    "Thursday" => 3,
    "Friday" => 4,
    "Saturday" => 5,
    "Sunday" => 6,
    "Mon" => 0,
    "Tue" => 1,
    "Wed" => 2,
    "Thu" => 3,
    "Fri" => 4,
    "Sat" => 5,
    "Sun" => 6,
    "SignificantUpdate" => 1,
    "MovementUpdate" => 2,
    "SleepUpdate" => 3,
    "Rectangular" => 0,
    "Round" => 1
  }

  @spec dispatch_expr(String.t() | nil, map() | nil, map()) :: {String.t(), String.t() | nil}
  def dispatch_expr(message, message_value, tags) when is_map(tags) do
    ctor =
      message
      |> to_string_or_nil()
      |> case do
        nil -> nil
        msg -> msg |> String.trim() |> String.split(~r/\s+/, parts: 2) |> List.first()
      end

    cond do
      wildcard_message?(message) ->
        {"0", nil}

      wildcard_update_branch?(message) ->
        dispatch_with_optional_payload(ctor, TimelineMessageValue.sample_for_ctor(ctor), tags, "&app")

      true ->
        tag = ctor && Map.get(tags, normalize_ctor(ctor))

        cond do
          is_nil(tag) ->
            {"0", "missing_tag:#{inspect(ctor)}"}

          is_nil(message_value) ->
            {"elmc_pebble_dispatch_int(&app, #{tag})", nil}

          true ->
            {payload_expr, err} = wire_value_expr(message_value)

            if err do
              {"0", err}
            else
              {"elmc_pebble_dispatch_tag_payload(&app, #{tag}, #{payload_expr})", nil}
            end
        end
    end
  end

  defp dispatch_with_optional_payload(_ctor, sample, tags, app_expr) when not is_nil(sample) do
    tag = Map.get(tags, normalize_ctor(_ctor))

    if is_nil(tag) do
      {"0", "missing_tag:#{inspect(_ctor)}"}
    else
      {payload_expr, err} = wire_value_expr(sample)

      if err do
        {"0", err}
      else
        {"elmc_pebble_dispatch_tag_payload(#{app_expr}, #{tag}, #{payload_expr})", nil}
      end
    end
  end

  defp dispatch_with_optional_payload(ctor, nil, tags, app_expr) do
    tag = ctor && Map.get(tags, normalize_ctor(ctor))

    if is_nil(tag) do
      {"0", "missing_tag:#{inspect(ctor)}"}
    else
      {"elmc_pebble_dispatch_int(#{app_expr}, #{tag})", nil}
    end
  end

  defp wildcard_update_branch?(message) when is_binary(message) do
    String.match?(String.trim(message), ~r/ _\z/)
  end

  defp wildcard_update_branch?(_), do: false

  def dispatch_expr(_message, _message_value, _tags), do: {"0", "invalid_message"}

  @spec wire_value_expr(term()) :: {String.t(), String.t() | nil}
  def wire_value_expr(value) when is_integer(value), do: {"harness_int(#{value})", nil}
  def wire_value_expr(value) when is_boolean(value), do: {"harness_bool(#{if value, do: 1, else: 0})", nil}

  def wire_value_expr(value) when is_binary(value),
    do: {"harness_string(#{inspect(value)})", nil}

  def wire_value_expr(%{"ctor" => "FromPhone", "args" => [inner | _]}) when is_map(inner) do
    wire_value_expr(inner)
  end

  def wire_value_expr(%{"ctor" => ctor, "args" => args}) when is_binary(ctor) and is_list(args) do
    with {:ok, arg_exprs} <- wire_args(args) do
      case {ctor, arg_exprs} do
        {"Just", [inner]} ->
          {"harness_maybe_just(#{inner})", nil}

        {"Nothing", []} ->
          {"harness_maybe_nothing()", nil}

        {"Ok", [inner]} ->
          {"harness_result_ok(#{inner})", nil}

        {"Err", [inner]} ->
          {"harness_result_err(#{inner})", nil}

        {"()", []} ->
          {"harness_unit()", nil}

        {name, []} ->
          cond do
            tag = Map.get(@weather_condition_tags, name) ->
              {"harness_int(#{tag})", nil}

            true ->
              case nullary_union_tag(name) do
                {:ok, tag} ->
                  {"harness_tuple2_take(harness_int(#{tag}), harness_unit())", nil}

                :error ->
                  {"harness_tuple2_take(harness_int(0), harness_unit())", "union_tag_stub:#{name}"}
              end
          end

        {name, arg_exprs} ->
          case phone_to_watch_payload(name, arg_exprs) do
            {:ok, expr} -> {expr, nil}
            :error -> record_expr(name, arg_exprs)
          end
      end
    end
  end

  def wire_value_expr(%{} = map) do
    fields =
      case ordered_record_fields(map) do
        nil ->
          map
          |> Enum.sort_by(fn {k, _} -> to_string(k) end)
          |> Enum.map(fn {k, v} ->
            with {expr, nil} <- wire_value_expr(v), do: {to_string(k), expr}
          end)

        ordered ->
          ordered
      end

    record_fields_expr(fields)
  catch
    {:error, err} -> {"NULL", err}
  end

  def wire_value_expr(value) when is_list(value) do
    if Enum.all?(value, &is_integer/1) do
      ints = Enum.join(value, ", ")
      count = length(value)
      {"harness_int_list((elmc_int_t[]){#{ints}}, #{count})", nil}
    else
      {"NULL", "unsupported_list_payload"}
    end
  end

  def wire_value_expr(_), do: {"NULL", "unsupported_wire_value"}

  defp wire_args(args) when is_list(args) do
    args
    |> Enum.reduce_while({[], nil}, fn arg, {acc, _} ->
      case wire_value_expr(arg) do
        {expr, nil} -> {:cont, {[expr | acc], nil}}
        {_expr, err} -> {:halt, {acc, err}}
      end
    end)
    |> case do
      {exprs, nil} -> {:ok, Enum.reverse(exprs)}
      {_exprs, err} -> {:error, err}
    end
  end

  defp ordered_record_fields(%{"year" => _, "month" => _} = map) do
    record_fields_in_order(map, ~w(year month day dayOfWeek hour minute second utcOffsetMinutes))
  end

  defp ordered_record_fields(%{"year" => _, "mon" => _} = map) do
    record_fields_in_order(map, ~w(year mon mday wday hour min sec isdst))
  end

  defp ordered_record_fields(%{"hour" => _, "min" => _} = map) do
    record_fields_in_order(map, ~w(hour min))
  end

  defp ordered_record_fields(_), do: nil

  defp record_fields_in_order(map, keys) do
    Enum.reduce(keys, [], fn key, acc ->
      case Map.fetch(map, key) do
        {:ok, value} ->
          case wire_value_expr(value) do
            {expr, nil} -> [{key, expr} | acc]
            {_expr, err} -> throw({:error, err})
          end

        :error ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp record_expr(name, arg_exprs) do
    fields =
      arg_exprs
      |> Enum.with_index(1)
      |> Enum.map(fn {expr, idx} -> {"field#{idx}", expr} end)

    record_fields_expr(fields, name)
  end

  defp record_fields_expr(fields, _label \\ "record") do
    count = length(fields)
    args = fields |> Enum.map(fn {_k, expr} -> expr end) |> Enum.join(", ")
    {"make_record_#{count}(#{args})", nil}
  end

  defp normalize_ctor(name) when is_binary(name) do
    name
    |> String.replace(~r/[^A-Za-z0-9]/, "")
    |> String.upcase()
  end

  defp wildcard_message?(message) when is_binary(message), do: String.trim(message) == "_"
  defp wildcard_message?(_), do: false

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)

  defp nullary_union_tag(name) when is_binary(name) do
    case Map.fetch(@nullary_union_tags, name) do
      {:ok, tag} -> {:ok, tag}
      :error -> :error
    end
  end

  defp phone_to_watch_payload(name, arg_exprs) when is_binary(name) and is_list(arg_exprs) do
    with {:ok, tag} <- Map.fetch(@phone_to_watch_tags, name) do
      {:ok, "harness_tuple2_take(harness_int(#{tag}), #{nest_tuple2_args(arg_exprs)})"}
    end
  end

  defp nest_tuple2_args([expr]), do: expr

  defp nest_tuple2_args([expr | rest]),
    do: "harness_tuple2_take(#{expr}, #{nest_tuple2_args(rest)})"
end
