defmodule Elmc.Backend.Bytecode.TierGate do
  @moduledoc false

  @generated_text_share 0.35
  @large_rc_fn_bytes 400
  @min_large_rc_fns 10

  @type metrics :: %{
          optional(:generated_text_bytes) => non_neg_integer(),
          optional(:pebble_app_bin_bytes) => non_neg_integer(),
          optional(:rc_fn_text_sizes) => [{String.t(), non_neg_integer()}]
        }

  @spec eligible?(metrics()) :: boolean()
  def eligible?(%{} = metrics) do
    generated = Map.get(metrics, :generated_text_bytes, 0)
    bin = Map.get(metrics, :pebble_app_bin_bytes, 0)
    rc_sizes = Map.get(metrics, :rc_fn_text_sizes, [])

    bin > 0 and
      generated / bin > @generated_text_share and
      Enum.count(rc_sizes, fn {_name, bytes} -> bytes > @large_rc_fn_bytes end) >= @min_large_rc_fns
  end

  def eligible?(_), do: false

  @spec criteria() :: map()
  def criteria do
    %{
      generated_text_share: @generated_text_share,
      large_rc_fn_bytes: @large_rc_fn_bytes,
      min_large_rc_fns: @min_large_rc_fns
    }
  end

  @spec report(metrics()) :: map()
  def report(%{} = metrics) do
    generated = Map.get(metrics, :generated_text_bytes, 0)
    bin = Map.get(metrics, :pebble_app_bin_bytes, 0)
    rc_sizes = Map.get(metrics, :rc_fn_text_sizes, [])
    large = Enum.filter(rc_sizes, fn {_name, bytes} -> bytes > @large_rc_fn_bytes end)

    %{
      eligible: eligible?(metrics),
      generated_text_bytes: generated,
      pebble_app_bin_bytes: bin,
      generated_text_share: if(bin > 0, do: generated / bin, else: 0.0),
      large_rc_fn_count: length(large),
      criteria: criteria()
    }
  end
end
