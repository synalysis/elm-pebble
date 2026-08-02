defmodule Elmx.Pebble.Contract.TemplateSdkAssert do
  @moduledoc false

  @template_c Path.expand(
                "../../../../../ide/priv/pebble_app_template/src/c/pebble_app_template.c",
                __DIR__
              )

  @animation_dispatch_sources [
    Path.expand(
      "../../../../../elmc/lib/elmc/backend/pebble/source_writer/draw_runtime/bitmap_sequence_instances.ex",
      __DIR__
    ),
    Path.expand(
      "../../../../../elmc/lib/elmc/backend/pebble/source_writer/draw_runtime/vector_sequence_instances.ex",
      __DIR__
    )
  ]

  @spec template_source!() :: String.t()
  def template_source! do
    File.read!(@template_c)
  end

  @spec cmd_case_body(String.t(), String.t()) :: String.t()
  def cmd_case_body(source, c_macro) when is_binary(source) and is_binary(c_macro) do
    needle = "case #{c_macro}:"

    case String.split(source, needle, parts: 2) do
      [_, rest] ->
        case Regex.run(~r/\ncase ELMC_PEBBLE_CMD_/, rest, return: :index) do
          [{pos, _}] -> String.slice(rest, 0, pos)
          _ -> rest
        end

      _ ->
        ""
    end
  end

  @spec assert_cmd_sdk_calls!(String.t(), map()) :: :ok
  def assert_cmd_sdk_calls!(source, %{c_macro: macro, sdk_calls: calls, id: id}) do
    body = cmd_case_body(source, macro)

    if body == "" do
      raise "pebble_app_template.c missing case #{macro} for cmd #{id}"
    end

    for sym <- calls do
      unless String.contains?(body, sym) do
        raise "case #{macro} missing SDK symbol #{sym} (cmd #{id})"
      end
    end

    :ok
  end

  @spec assert_sub_sdk_calls!(String.t(), map(), keyword()) :: :ok
  def assert_sub_sdk_calls!(template_source, %{sdk_calls: calls, id: id}, opts \\ []) do
    if calls == [] do
      :ok
    else
      extra_sources = Keyword.get(opts, :extra_sources, [])

      sources =
        [template_source | extra_sources]
        |> Enum.map(fn
          {:file, path} -> File.read!(path)
          bin when is_binary(bin) -> bin
        end)

      for sym <- calls do
        unless Enum.any?(sources, &String.contains?(&1, sym)) do
          raise "missing subscription/runtime SDK symbol #{sym} for sub #{id}"
        end
      end

      :ok
    end
  end

  @spec animation_dispatch_sources!() :: String.t()
  def animation_dispatch_sources! do
    @animation_dispatch_sources
    |> Enum.map(&File.read!/1)
    |> Enum.join("\n")
  end
end
