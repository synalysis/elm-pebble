defmodule Elmc.Backend.SizeProfile do
  @moduledoc false

  alias Elmc.Types

  @type profile :: :default | :balanced | :size
  @type compile_options :: Types.compile_options()

  @spec apply(compile_options()) :: compile_options()
  def apply(opts) when is_map(opts) do
    opts
    |> Map.get(:codegen_profile, :default)
    |> normalize_profile()
    |> then(&apply_profile(&1, opts))
  end

  @spec profile?(compile_options(), profile()) :: boolean()
  def profile?(opts, profile) when is_map(opts) and profile in [:default, :balanced, :size] do
    normalize_profile(Map.get(opts, :codegen_profile, :default)) == profile
  end

  @spec size?(compile_options()) :: boolean()
  def size?(opts) when is_map(opts), do: profile?(opts, :size)

  defp normalize_profile(:size), do: :size
  defp normalize_profile(:balanced), do: :balanced
  defp normalize_profile(:default), do: :default
  defp normalize_profile("size"), do: :size
  defp normalize_profile("balanced"), do: :balanced
  defp normalize_profile(_), do: :default

  defp apply_profile(:default, opts), do: opts

  defp apply_profile(:balanced, opts) do
    opts
    |> Map.put_new(:strip_dead_code, true)
    |> Map.put_new(:plan_ir_mode, :primary)
  end

  defp apply_profile(:size, opts) do
    opts
    |> Map.put_new(:strip_dead_code, true)
    |> Map.put_new(:prune_runtime, true)
    |> Map.put_new(:prune_native_wrappers, true)
    |> Map.put_new(:plan_ir_mode, :primary)
    |> Map.put_new(:plan_ir_strict, true)
    |> Map.put_new(:enum_tag_peel, true)
    |> Map.put_new(:plan_emit, :state_switch)
    |> Map.put_new(:fusion_supersede_native, true)
    |> Map.put_new(:size_mod_by_fast, true)
    |> Map.put_new(:size_native_compare, true)
    |> Map.put_new(:size_prune_capabilities, true)
    |> Map.put_new(:size_aggressive_direct_render, true)
    |> then(fn sized ->
      if Map.get(sized, :direct_render_only) == false do
        sized
      else
        Map.put_new(sized, :direct_render_only, true)
      end
    end)
  end

  @spec plan_emit_mode(keyword() | compile_options()) :: :goto | :state_switch
  def plan_emit_mode(opts) when is_list(opts) do
    plan_emit_mode(Map.new(opts))
  end

  def plan_emit_mode(opts) when is_map(opts) do
    if size?(opts) and Map.get(opts, :plan_emit) == :state_switch do
      :state_switch
    else
      :goto
    end
  end

  @spec enum_tag_peel?(compile_options()) :: boolean()
  def enum_tag_peel?(opts) when is_map(opts) do
    size?(opts) and Map.get(opts, :enum_tag_peel, false) == true
  end

  @spec mod_by_fast?(compile_options()) :: boolean()
  def mod_by_fast?(opts) when is_map(opts) do
    size?(opts) and Map.get(opts, :size_mod_by_fast, false) == true
  end

  @spec native_compare?(compile_options()) :: boolean()
  def native_compare?(opts) when is_map(opts) do
    size?(opts) and Map.get(opts, :size_native_compare, false) == true
  end

  @spec fusion_supersede_native?(compile_options()) :: boolean()
  def fusion_supersede_native?(opts) when is_map(opts) do
    size?(opts) and Map.get(opts, :fusion_supersede_native, false) == true
  end

  @spec aggressive_direct_render?(compile_options()) :: boolean()
  def aggressive_direct_render?(opts) when is_map(opts) do
    size?(opts) and Map.get(opts, :size_aggressive_direct_render, false) == true
  end

  @spec prune_capabilities?(compile_options()) :: boolean()
  def prune_capabilities?(opts) when is_map(opts) do
    size?(opts) and Map.get(opts, :size_prune_capabilities, false) == true
  end

  @spec plan_state_switch_thresholds(compile_options()) ::
          %{min_blocks: pos_integer(), max_owned_slots: pos_integer()}
  def plan_state_switch_thresholds(_opts) do
    %{min_blocks: 8, max_owned_slots: 12}
  end

  @spec plan_union_tag_switch_min_arms(compile_options()) :: pos_integer()
  def plan_union_tag_switch_min_arms(opts) when is_map(opts) do
    if size?(opts), do: 2, else: 3
  end
end
