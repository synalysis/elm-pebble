defmodule Elmc.TestSupport.TeaScenarioProtocol do
  @moduledoc false

  alias Elmx.TeaPlaybook.Protocol

  @type phone_ctor :: Protocol.phone_ctor()

  @spec types_path(String.t()) :: String.t() | nil
  defdelegate types_path(template), to: Protocol

  @spec phone_to_watch_constructors(String.t()) :: [phone_ctor()]
  defdelegate phone_to_watch_constructors(template), to: Protocol

  @spec phone_tag(String.t(), String.t()) :: non_neg_integer() | nil
  defdelegate phone_tag(template, ctor_name), to: Protocol

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

  defp builder_for(%{name: "ProvideSun", tag: tag}) do
    """
    static ElmcValue *tea_provide_sun(void) {
      ElmcValue *payload = tea_harness_tuple2_take(
          tea_harness_int(360),
          tea_harness_tuple2_take(tea_harness_int(1080), tea_harness_int(1)));
      return tea_harness_phone_union(#{tag}, payload);
    }
    """
  end

  defp builder_for(%{name: "ProvideWeather", tag: tag}) do
    """
    static ElmcValue *tea_provide_weather(void) {
      ElmcValue *payload = tea_harness_tuple2_take(
          tea_harness_union_int(1, 210),
          tea_harness_tuple2_take(
              tea_harness_int(1),
              tea_harness_tuple2_take(
                  tea_harness_int(0),
                  tea_harness_tuple2_take(tea_harness_int(0), tea_harness_int(1013)))));
      return tea_harness_phone_union(#{tag}, payload);
    }
    """
  end

  defp builder_for(%{name: "ProvideCondition", tag: tag}) do
    """
    static ElmcValue *tea_provide_condition(void) {
      return tea_harness_phone_union(#{tag}, tea_harness_int(1));
    }
    """
  end

  defp builder_for(%{name: "ProvideTemperature", tag: tag}) do
    """
    static ElmcValue *tea_provide_temperature(void) {
      return tea_harness_phone_union(#{tag}, tea_harness_union_int(1, 210));
    }
    """
  end

  defp builder_for(%{name: "ProvideMoonPhase", tag: tag}) do
    """
    static ElmcValue *tea_provide_moon_phase(void) {
      return tea_harness_phone_union(#{tag}, tea_harness_int(250000));
    }
    """
  end

  defp builder_for(%{name: "ProvideMoon", tag: tag}) do
    """
    static ElmcValue *tea_provide_moon(void) {
      ElmcValue *payload = tea_harness_tuple2_take(
          tea_harness_int(360),
          tea_harness_tuple2_take(tea_harness_int(1080), tea_harness_int(250000)));
      return tea_harness_phone_union(#{tag}, payload);
    }
    """
  end

  defp builder_for(_), do: nil
end
