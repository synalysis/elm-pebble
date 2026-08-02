defmodule Elmc.TestSupport.TeaScenarioProtocol do
  @moduledoc false

  alias Elmx.TeaPlaybook.Protocol

  @type phone_ctor :: Protocol.phone_ctor()

  @spec types_path(String.t()) :: String.t() | nil
  defdelegate types_path(template), to: Protocol

  @spec phone_to_watch_constructors(String.t()) :: [phone_ctor()]
  defdelegate phone_to_watch_constructors(template), to: Protocol

  @spec phone_tag(String.t(), String.t()) :: pos_integer() | nil
  defdelegate phone_tag(template, ctor_name), to: Protocol

  @spec builder_fn_name(String.t()) :: String.t()
  def builder_fn_name(ctor_name) when is_binary(ctor_name) do
    "tea_from_phone_" <>
      (ctor_name
       |> Macro.underscore()
       |> String.replace(~r/[^a-z0-9_]/, ""))
  end

  @spec supported_ctor?(phone_ctor()) :: boolean()
  def supported_ctor?(ctor), do: match?({:ok, _}, builder_body(ctor))

  @spec harness_c(String.t()) :: String.t() | nil
  def harness_c(template) do
    ctors = phone_to_watch_constructors(template)

    if ctors == [] do
      nil
    else
      builders =
        ctors
        |> Enum.map(&builder_for/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")

      if builders == "" do
        nil
      else
        tags =
          Enum.map_join(ctors, "\n", fn %{name: name, tag: tag} ->
            "/* #{name}=#{tag} */"
          end)

        """
        #{tags}

        #{builders}
        """
      end
    end
  end

  defp builder_for(ctor) do
    case builder_body(ctor) do
      {:ok, body} ->
        fn_name = builder_fn_name(ctor.name)

        """
        static ElmcValue *#{fn_name}(void) {
        #{body}
        }
        """

      :error ->
        nil
    end
  end

  defp builder_body(%{name: "ProvideSun", tag: tag}) do
    {:ok,
     """
       ElmcValue *payload = tea_harness_tuple2_take(
           tea_harness_int(360),
           tea_harness_tuple2_take(tea_harness_int(1080), tea_harness_int(1)));
       return tea_harness_phone_union(#{tag}, payload);
     """}
  end

  defp builder_body(%{name: "ProvideWeather", tag: tag, arity: 2}) do
    {:ok,
     """
       return tea_harness_phone_union(#{tag},
           tea_harness_tuple2_take(tea_harness_int(18), tea_harness_int(1)));
     """}
  end

  defp builder_body(%{name: "ProvideWeather", tag: tag}) do
    {:ok,
     """
       ElmcValue *payload = tea_harness_tuple2_take(
           tea_harness_union_int(1, 210),
           tea_harness_tuple2_take(
               tea_harness_int(1),
               tea_harness_tuple2_take(
                   tea_harness_int(0),
                   tea_harness_tuple2_take(tea_harness_int(0), tea_harness_int(1013)))));
       return tea_harness_phone_union(#{tag}, payload);
     """}
  end

  defp builder_body(%{name: "ProvideCondition", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_int(1));\n"}
  end

  defp builder_body(%{name: "ProvideTemperature", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_union_int(1, 210));\n"}
  end

  defp builder_body(%{name: "ProvideMoonPhase", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_int(250000));\n"}
  end

  defp builder_body(%{name: "ProvideMoon", tag: tag}) do
    {:ok,
     """
       ElmcValue *payload = tea_harness_tuple2_take(
           tea_harness_int(360),
           tea_harness_tuple2_take(tea_harness_int(1080), tea_harness_int(250000)));
       return tea_harness_phone_union(#{tag}, payload);
     """}
  end

  defp builder_body(%{name: "ProvideTimezone", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_int(120));\n"}
  end

  defp builder_body(%{name: "ClearTide", tag: tag}) do
    {:ok, "  return tea_harness_int(#{tag});\n"}
  end

  defp builder_body(%{name: "Pong", tag: tag}) do
    {:ok, "  return tea_harness_int(#{tag});\n"}
  end

  defp builder_body(%{name: "EchoColor", tag: tag}) do
    # Color.Red = 1
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_int(1));\n"}
  end

  defp builder_body(%{name: "EchoMeasure", tag: tag}) do
    # Measure.Liters 3 — Liters tag = 1
    {:ok,
     """
       return tea_harness_phone_union(#{tag}, tea_harness_phone_union(1, tea_harness_int(3)));
     """}
  end

  defp builder_body(%{name: "EchoPoint", tag: tag}) do
    {:ok,
     """
       ElmcValue *fields[2] = { tea_harness_int(1), tea_harness_int(2) };
       ElmcValue *point = NULL;
       if (elmc_record_new_values(&point, 2, fields) != RC_SUCCESS) return NULL;
       elmc_release(fields[0]);
       elmc_release(fields[1]);
       return tea_harness_phone_union(#{tag}, point);
     """}
  end

  defp builder_body(%{name: "EchoCounts", tag: tag}) do
    {:ok,
     """
       static const elmc_int_t vals[3] = { 1, 2, 3 };
       ElmcValue *list = NULL;
       if (elmc_list_from_int_array(&list, vals, 3) != RC_SUCCESS) return NULL;
       return tea_harness_phone_union(#{tag}, list);
     """}
  end

  defp builder_body(%{name: "PushBool", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_bool(true));\n"}
  end

  defp builder_body(%{name: "PushString", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_string(\"elm\"));\n"}
  end

  defp builder_body(%{name: "PushPoints", tag: tag}) do
    {:ok,
     """
       ElmcValue *fields[2] = { tea_harness_int(4), tea_harness_int(5) };
       ElmcValue *point = NULL;
       if (elmc_record_new_values(&point, 2, fields) != RC_SUCCESS) return NULL;
       elmc_release(fields[0]);
       elmc_release(fields[1]);
       ElmcValue *items[1] = { point };
       ElmcValue *list = NULL;
       if (elmc_list_from_values(&list, items, 1) != RC_SUCCESS) return NULL;
       elmc_release(point);
       return tea_harness_phone_union(#{tag}, list);
     """}
  end

  defp builder_body(%{name: "PushLabels", tag: tag}) do
    # Dict is a list of (key, value) tuples; avoid pruned elmc_dict_insert/from_list.
    {:ok,
     """
       ElmcValue *pair = tea_harness_tuple2_take(tea_harness_string(\"k\"), tea_harness_int(9));
       ElmcValue *items[1] = { pair };
       ElmcValue *dict = NULL;
       if (elmc_list_from_values(&dict, items, 1) != RC_SUCCESS) return NULL;
       elmc_release(pair);
       return tea_harness_phone_union(#{tag}, dict);
     """}
  end

  defp builder_body(%{name: "ProvideBattery", tag: tag}) do
    {:ok,
     """
       return tea_harness_phone_union(#{tag},
           tea_harness_tuple2_take(tea_harness_int(88), tea_harness_bool(true)));
     """}
  end

  defp builder_body(%{name: "ProvideLocale", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_string(\"en-US\"));\n"}
  end

  defp builder_body(%{name: "ProvideConnectivity", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_bool(true));\n"}
  end

  defp builder_body(%{name: "ProvideNotifications", tag: tag}) do
    {:ok,
     """
       return tea_harness_phone_union(#{tag},
           tea_harness_tuple2_take(tea_harness_bool(true), tea_harness_bool(false)));
     """}
  end

  defp builder_body(%{name: "ProvideNextEvent", tag: tag}) do
    {:ok,
     """
       ElmcValue *payload = tea_harness_tuple2_take(
           tea_harness_string(\"Standup\"),
           tea_harness_tuple2_take(tea_harness_int(9), tea_harness_int(30)));
       return tea_harness_phone_union(#{tag}, payload);
     """}
  end

  defp builder_body(%{name: "NoUpcomingEvents", tag: tag}) do
    {:ok, "  return tea_harness_int(#{tag});\n"}
  end

  defp builder_body(%{name: "ProvidePosition", tag: tag}) do
    {:ok,
     """
       ElmcValue *payload = tea_harness_tuple2_take(
           tea_harness_int(12345000),
           tea_harness_tuple2_take(tea_harness_int(-98765000), tea_harness_int(25)));
       return tea_harness_phone_union(#{tag}, payload);
     """}
  end

  defp builder_body(%{name: "ProvideTheme", tag: tag}) do
    # Theme.Dark=1, Units.Metric=1 (1-based)
    {:ok,
     """
       return tea_harness_phone_union(#{tag},
           tea_harness_tuple2_take(tea_harness_int(1), tea_harness_int(1)));
     """}
  end

  defp builder_body(%{name: "SettingsReady", tag: tag}) do
    {:ok, "  return tea_harness_int(#{tag});\n"}
  end

  defp builder_body(%{name: "SettingsClosed", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_int(1));\n"}
  end

  defp builder_body(%{name: "ProvideWebSocketStatus", tag: tag}) do
    {:ok,
     """
       return tea_harness_phone_union(#{tag},
           tea_harness_tuple2_take(tea_harness_int(1), tea_harness_string(\"connected\")));
     """}
  end

  defp builder_body(%{name: "ProvideTimelineToken", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_string(\"tea-token\"));\n"}
  end

  defp builder_body(%{name: "ProvideTimelineStatus", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_int(1));\n"}
  end

  defp builder_body(%{name: "ProvideEnvironment", tag: tag}) do
    {:ok,
     """
       ElmcValue *payload = tea_harness_tuple2_take(
           tea_harness_int(360),
           tea_harness_tuple2_take(tea_harness_int(1080), tea_harness_int(500000)));
       return tea_harness_phone_union(#{tag}, payload);
     """}
  end

  defp builder_body(%{name: "ProvideFigure", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_int(1));\n"}
  end

  defp builder_body(%{name: "BeginFigure", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_int(1));\n"}
  end

  defp builder_body(%{name: "EndFigure", tag: tag}) do
    {:ok, "  return tea_harness_phone_union(#{tag}, tea_harness_int(1));\n"}
  end

  defp builder_body(%{name: "ProvidePiece", tag: tag}) do
    {:ok,
     """
       static const elmc_int_t vals[4] = { 0, 3, -3, -5 };
       ElmcValue *list = NULL;
       if (elmc_list_from_int_array(&list, vals, 4) != RC_SUCCESS) return NULL;
       return tea_harness_phone_union(#{tag},
           tea_harness_tuple2_take(tea_harness_int(0), list));
     """}
  end

  defp builder_body(_), do: :error
end
