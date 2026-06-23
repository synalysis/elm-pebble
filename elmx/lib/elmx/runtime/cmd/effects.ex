defmodule Elmx.Runtime.Cmd.Effects do
  @moduledoc false

  alias Elmx.Runtime.Cmd.{Companion, Wire}
  alias Elmx.Types

  @doc """
  Registers a Pebble subscription for debugger stepping (contract-driven `target` string).
  """
  @spec subscription_register(String.t(), Types.subscription_register_opts()) :: Types.wire_cmd()
  def subscription_register(target, opts \\ []) when is_binary(target) do
    {message, message_value} =
      case Keyword.get(opts, :callback) do
        nil -> {"", nil}
        callback -> Wire.message_wire(callback)
      end

    base = %{
      "kind" => "cmd.subscription.register",
      "package" => "elm-pebble/elm-watch",
      "target" => target,
      "message" => message
    }

    base
    |> Companion.maybe_put_field("interval_ms", Keyword.get(opts, :interval_ms))
    |> Companion.maybe_put_field("message_value", message_value)
  end

  @doc """
  Side-effect command the IDE may simulate (vibes, light) without a followup message.
  """
  @spec effect(String.t(), Types.effect_cmd_opts()) :: Types.wire_cmd()
  def effect(kind, opts \\ []) when is_binary(kind) do
    %{
      "kind" => "cmd.effect." <> kind,
      "package" => "elm-pebble/elm-watch"
    }
    |> Companion.maybe_put_field("variant", Keyword.get(opts, :variant))
    |> Companion.maybe_put_field("pattern", Keyword.get(opts, :pattern))
    |> merge_extra_fields(Keyword.get(opts, :extra))
  end

  defp merge_extra_fields(cmd, extra) when is_map(cmd) and is_map(extra) do
    Enum.reduce(extra, cmd, fn {key, value}, acc ->
      Companion.maybe_put_field(acc, to_string(key), value)
    end)
  end

  defp merge_extra_fields(cmd, _), do: cmd

  @doc """
  Pebble backlight cmd from `Maybe Bool` (Nothing → interaction, Just False → disable, Just True → enable).
  """
  @spec backlight_from_maybe(Types.maybe_like()) :: Types.wire_cmd()
  def backlight_from_maybe(maybe) do
    mode =
      case maybe do
        :Nothing -> 0
        %{"ctor" => "Nothing"} -> 0
        %{ctor: :Nothing} -> 0
        {:Just, false} -> 1
        {:Just, true} -> 2
        %{"ctor" => "Just", "args" => [false]} -> 1
        %{"ctor" => "Just", "args" => [true]} -> 2
        %{ctor: :Just, args: [false]} -> 1
        %{ctor: :Just, args: [true]} -> 2
        _ -> 0
      end

    %{
      "kind" => "cmd.backlight",
      "package" => "pebble/cmd",
      "mode" => mode
    }
  end

end
