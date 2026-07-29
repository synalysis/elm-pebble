defmodule Elmc.Backend.CCodegen.UnsupportedSurface do
  @moduledoc false

  alias Elmc.Backend.Plan.StrictPolicy

  @type reason :: %{
          optional(:kind) => :cmd | :sub | :expr | :arity,
          optional(:target) => String.t() | nil,
          optional(:arity) => non_neg_integer() | nil,
          optional(:op) => atom() | nil,
          optional(:detail) => String.t() | nil
        }

  @cmd_prefixes ~w(
    Pebble.Cmd.
    Cmd.
    Elm.Kernel.PebbleWatch.
    Pebble.Storage.
    Pebble.Time.
    Pebble.Speaker.
    Pebble.Vibes.
    Pebble.Wakeup.
    Pebble.Log.
    Pebble.WatchInfo.
    Pebble.Health.
    Pebble.DataLog.
    Pebble.Compass.
    Pebble.Dictation.
    Pebble.Light.
    Pebble.System.
    Pebble.UnobstructedArea.
    Pebble.Hardware.
    Pebble.Internal.
    Random.generate
    Elm.Kernel.Random.generate
  )

  @sub_prefixes ~w(
    Pebble.Events.
    Pebble.Button.
    Pebble.Frame.
    Pebble.Accel.
    Pebble.System.
    Pebble.Health.
    Pebble.AppFocus.
    Pebble.Light.
    Pebble.Platform.
    Pebble.Speaker.
    Pebble.Compass.
    Pebble.Dictation.
    Pebble.UnobstructedArea.
    Companion.Watch.
    Sub.
  )

  @spec unsupported_expr(reason()) :: map()
  def unsupported_expr(attrs) when is_map(attrs) do
    attrs
    |> Map.put(:op, :unsupported)
    |> tap(&record_unsupported/1)
  end

  @spec record_cmd(String.t(), non_neg_integer(), String.t() | nil) :: :ok
  def record_cmd(target, arity, detail \\ nil) when is_binary(target) and is_integer(arity) do
    record_unsupported(%{kind: :cmd, target: target, arity: arity, detail: detail})
  end

  @spec record_sub(String.t(), non_neg_integer(), String.t() | nil) :: :ok
  def record_sub(target, arity, detail \\ nil) when is_binary(target) and is_integer(arity) do
    record_unsupported(%{kind: :sub, target: target, arity: arity, detail: detail})
  end

  @spec record_expr(reason()) :: :ok
  def record_expr(reason) when is_map(reason), do: record_unsupported(reason)

  @spec record_missing_special(String.t(), [term()]) :: :ok
  def record_missing_special(target, args) when is_binary(target) and is_list(args) do
    arity = length(args)

    cond do
      cmd_target?(target) -> record_cmd(target, arity, "no lowering for cmd target")
      sub_target?(target) -> record_sub(target, arity, "no lowering for subscription target")
      true -> :ok
    end
  end

  @spec record_from_expr(map()) :: :ok
  def record_from_expr(%{op: :unsupported} = expr) do
    case Map.get(expr, :kind) do
      :cmd ->
        record_cmd(Map.get(expr, :target, "unknown"), Map.get(expr, :arity, 0), Map.get(expr, :detail))

      :sub ->
        record_sub(Map.get(expr, :target, "unknown"), Map.get(expr, :arity, 0), Map.get(expr, :detail))

      _ ->
        record_unsupported(%{
          kind: :expr,
          op: Map.get(expr, :reason_op) || Map.get(expr, :op),
          target: Map.get(expr, :target),
          detail: Map.get(expr, :detail)
        })
    end
  end

  def record_from_expr(_), do: :ok

  @spec compile_warnings(keyword()) :: [map()]
  def compile_warnings(opts \\ []) do
    Process.get(:elmc_compile_warnings, [])
    |> Enum.filter(fn
      %{"source" => source} when source in ["elmc/cmd", "elmc/subscriptions", "elmc/unsupported"] ->
        true

      %{source: source} when source in [:elmc_cmd, "elmc/cmd", :elmc_subscriptions, "elmc/subscriptions", :elmc_unsupported, "elmc/unsupported"] ->
        true

      _ ->
        false
    end)
    |> Enum.map(&normalize_diagnostic(&1, opts))
    |> Enum.uniq_by(fn diag -> {diag["source"], diag["code"], diag["message"]} end)
  end

  @spec format_plan_reason(map() | atom() | nil) :: String.t()
  def format_plan_reason(nil), do: "unsupported"

  def format_plan_reason(:unsupported), do: "unsupported"

  def format_plan_reason(%{op: op, target: target} = reason) when is_binary(target) do
    base = "op=#{op} target=#{target}"
    append_detail(base, reason)
  end

  def format_plan_reason(%{op: op} = reason) when not is_nil(op) do
    append_detail("op=#{op}", reason)
  end

  def format_plan_reason({:verify, verify_reason, _}), do: "verify:#{verify_reason}"
  def format_plan_reason(other) when is_binary(other), do: other
  def format_plan_reason(other), do: inspect(other)

  @spec fallback_message(String.t(), String.t(), map() | nil) :: String.t()
  def fallback_message(mod, name, reason) do
    detail =
      case reason do
        %{op: _} = r -> format_plan_reason(r)
        _ -> format_plan_reason(reason)
      end

    "Function #{mod}.#{name} could not be lowered via Plan IR (#{detail}); " <>
      "emitted unsupported stub (legacy C codegen removed)."
  end

  @spec cmd_target?(String.t()) :: boolean()
  def cmd_target?(target) when is_binary(target) do
    Enum.any?(@cmd_prefixes, &String.starts_with?(target, &1)) or
      String.ends_with?(target, ".none") or
      String.contains?(target, "storage") or
      String.contains?(target, "Cmd.") or
      String.contains?(target, "Random.generate")
  end

  @spec sub_target?(String.t()) :: boolean()
  def sub_target?(target) when is_binary(target) do
    Enum.any?(@sub_prefixes, &String.starts_with?(target, &1)) or
      String.contains?(target, "onSecondChange") or
      String.contains?(target, "onHourChange") or
      String.contains?(target, "onButton") or
      String.contains?(target, "Sub.")
  end

  defp record_unsupported(reason) when is_map(reason) do
    {source, code, message, severity} = diagnostic_fields(reason, Process.get(:elmc_codegen_opts, %{}))

    diagnostic = %{
      "severity" => severity,
      "source" => source,
      "code" => code,
      "message" => message
    }

    warnings = Process.get(:elmc_compile_warnings, [])
    Process.put(:elmc_compile_warnings, [diagnostic | warnings])
    :ok
  end

  defp diagnostic_fields(%{kind: :cmd, target: target, arity: arity} = reason, opts) do
    detail = Map.get(reason, :detail)

    message =
      "Unsupported Cmd target #{target}/#{arity}" <>
        if(detail, do: " (#{detail})", else: "")

    {"elmc/cmd", "unsupported_cmd", message, strict_severity(opts)}
  end

  defp diagnostic_fields(%{kind: :sub, target: target, arity: arity} = reason, opts) do
    detail = Map.get(reason, :detail)

    message =
      "Unsupported Sub target #{target}/#{arity}" <>
        if(detail, do: " (#{detail})", else: "")

    {"elmc/subscriptions", "unsupported_sub", message, strict_severity(opts)}
  end

  defp diagnostic_fields(reason, opts) do
    op = Map.get(reason, :op)
    target = Map.get(reason, :target)
    detail = Map.get(reason, :detail)

    message =
      ["Unsupported expression", op && "op=#{op}", target && "target=#{target}", detail]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    {"elmc/unsupported", "unsupported_expr", message, strict_severity(opts)}
  end

  defp strict_severity(opts) do
    if StrictPolicy.strict?(opts), do: "error", else: "warning"
  end

  defp normalize_diagnostic(diag, opts) when is_map(diag) do
    severity =
      case Map.get(diag, "severity") || Map.get(diag, :severity) do
        nil -> strict_severity(opts)
        value -> to_string(value)
      end

    %{
      "severity" => severity,
      "source" => Map.get(diag, "source") || Map.get(diag, :source),
      "code" => Map.get(diag, "code") || Map.get(diag, :code),
      "message" => Map.get(diag, "message") || Map.get(diag, :message)
    }
  end

  defp append_detail(base, reason) do
    case Map.get(reason, :error) || Map.get(reason, :kind) do
      nil -> base
      extra -> base <> " (#{extra})"
    end
  end
end
