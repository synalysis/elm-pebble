defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.Emit do
  @moduledoc """
  Table-driven C emit for Pebble subscription event dispatchers.
  """
  alias Elmc.Backend.Pebble.SourceWriter.EventDispatch.Registry
  alias Elmc.Backend.Pebble.Types

  @spec body(map()) :: Types.c_source()
  def body(bindings \\ %{}) do
    helpers =
      Registry.helpers()
      |> Enum.map(&Registry.helper_body/1)
      |> Enum.reject(&is_nil/1)

    decode = [app_message_decode(bindings)]

    dispatch_fns =
      Registry.entries()
      |> Enum.map(&emit_entry/1)

    tick_fn = [
      emit_entry(%{
        custom?: true,
        fn: "elmc_pebble_tick",
        params: [{"ElmcPebbleApp *", "app"}],
        body: Registry.tick_body(tick_has_payload?(bindings))
      })
    ]

    compass =
      if compass_events?(bindings) do
        [Registry.compass_body()]
      else
        []
      end

    host_api = [Registry.host_api_body()]

    (helpers ++ decode ++ dispatch_fns ++ tick_fn ++ compass ++ host_api)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> IO.iodata_to_binary()
  end

  defp app_message_decode(%{msg: %{value_decode_cases: values, key_decode_cases: keys}}) do
    Registry.app_message_decode_body(values, keys)
  end

  defp app_message_decode(_) do
    Registry.app_message_decode_body("", "")
  end

  defp tick_has_payload?(%{msg: %{tick_has_payload?: true}}), do: true
  defp tick_has_payload?(_), do: false

  defp compass_events?(%{compass_events?: true}), do: true
  defp compass_events?(_), do: false

  defp emit_entry(%{custom?: true, fn: fn_name, params: params, body: body}) do
    sig = signature(fn_name, params)

    """
    #{sig} {
      #{String.trim(body)}
    }

    """
  end

  defp emit_entry(%{fn: fn_name, params: params} = entry) do
    sig = signature(fn_name, params)
    body = standard_body(entry)

    """
    #{sig} {
      #{body}
    }

    """
  end

  defp signature(fn_name, params) do
    args =
      params
      |> Enum.map(fn {type, name} -> "#{type} #{name}" end)
      |> Enum.join(", ")

    "int #{fn_name}(#{args})"
  end

  defp standard_body(%{
         mask: mask,
         payload: payload,
         watchface_guard: watchface_guard?
       }) do
    guards = [
      "if (!app || !app->initialized) return -1;",
      if(watchface_guard?, do: "if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;", else: nil),
      "if (!elmc_pebble_is_subscribed(app, #{mask})) return -8;",
      "elmc_int_t tag = elmc_pebble_sub_tag(app, #{mask});",
      "if (tag <= 0) return -6;"
    ]

    dispatch = emit_payload(payload)

    (guards ++ [dispatch])
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&("  " <> &1))
    |> Enum.join("\n")
  end

  defp emit_payload(:dispatch_int) do
    "return elmc_pebble_dispatch_int(app, tag);"
  end

  defp emit_payload({:tag_value, opts}) do
    case Keyword.get(opts, :expr) do
      expr when is_binary(expr) ->
        "return elmc_pebble_dispatch_tag_value(app, tag, #{expr});"

      _ ->
        param = Keyword.fetch!(opts, :param)

        clamp_lines =
          case Keyword.get(opts, :clamp) do
            {lo, hi} ->
              default = Keyword.get(opts, :default_on_clamp)

              if default != nil do
                [
                  "if (#{param} < #{lo}) #{param} = #{default};",
                  "if (#{param} > #{hi}) #{param} = #{default};"
                ]
              else
                [
                  "if (#{param} < #{lo}) #{param} = #{lo};",
                  "if (#{param} > #{hi}) #{param} = #{hi};"
                ]
              end

            nil ->
              []
          end

        (clamp_lines ++ ["return elmc_pebble_dispatch_tag_value(app, tag, #{param});"])
        |> Enum.join("\n")
    end
  end

  defp emit_payload({:tag_bool, param: param}) do
    "return elmc_pebble_dispatch_tag_bool(app, tag, #{param});"
  end

  defp emit_payload({:record_int_fields, fields: fields}) do
    names =
      fields
      |> Enum.map(fn {name, _} -> "\"#{name}\"" end)
      |> Enum.join(", ")

    values =
      fields
      |> Enum.map(fn {_, param} -> param end)
      |> Enum.join(", ")

    count = length(fields)

    """
    const char *names[] = {#{names}};
    const int64_t values[] = {#{values}};
    return elmc_pebble_dispatch_tag_record_int_fields(app, tag, #{count}, names, values);
    """
    |> String.trim()
  end
end
