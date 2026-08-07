defmodule Elmc.Backend.CCodegen.PebbleWatchPhaseScope do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ProdMode
  alias Elmc.Backend.CCodegen.RcRuntimeEmit

  @phase_key :elmc_pebble_watch_phase_slot

  @spec enabled?() :: boolean()
  def enabled?, do: ProdMode.pebble_watch?()

  @spec reset!() :: :ok
  def reset! do
    Process.delete(@phase_key)
    :ok
  end

  @spec register_clamp_result?(map(), map(), map(), String.t()) :: :ok
  def register_clamp_result?(low, high, _value, out_var) when is_binary(out_var) do
    if enabled?() and clamp_0_million?(low, high) do
      Process.put(@phase_key, out_var)
    end

    :ok
  end

  def register_clamp_result?(_, _, _, _), do: :ok

  @spec phase_slot() :: String.t() | nil
  def phase_slot, do: Process.get(@phase_key)

  @spec angle_c_expr(String.t()) :: String.t()
  def angle_c_expr(phase_slot) do
    "((int32_t)((((int64_t)elmc_as_int(#{phase_slot})) * 65536LL) / 1000000LL))"
  end

  @spec try_compile_cos_sin(String.t(), map(), non_neg_integer()) ::
          {:ok, String.t(), String.t(), non_neg_integer()} | :error
  def try_compile_cos_sin(fun, env, counter) when fun in ["elmc_basics_sin", "elmc_basics_cos"] do
    case phase_slot() do
      slot when is_binary(slot) ->
        lookup = if fun == "elmc_basics_sin", do: "sin_lookup", else: "cos_lookup"
        next = counter + 1
        out = "native_watch_phase_trig_#{next}"
        angle = angle_c_expr(slot)

        code =
          RcRuntimeEmit.assign_call(
            env,
            out,
            "elmc_new_int",
            "#{lookup}(#{angle})"
          ) <> "\n"

        {:ok, code, out, next}

      _ ->
        :error
    end
  end

  def try_compile_cos_sin(_, _, _), do: :error

  defp clamp_0_million?(%{op: :int_literal, value: 0}, %{op: :int_literal, value: 1_000_000}), do: true
  defp clamp_0_million?(_, _), do: false
end
