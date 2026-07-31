defmodule Elmc.Backend.FlashVsHeap.Report do
  @moduledoc false

  alias Elmc.Backend.Bytecode.{TierGate, TierMetrics}
  alias Elmc.Backend.CCodegen.{ObjectTextEstimate, StackReport}
  alias Elmc.Backend.SizeProfile

  @contract "elmc.flash_vs_heap.v1"
  @report_name "flash_vs_heap.json"
  @flash_share_threshold 0.35
  @heap_owned_slot_threshold 16

  @type constraint :: :flash_bound | :heap_bound | :balanced

  @spec build(String.t(), keyword()) :: map()
  def build(out_dir, opts \\ []) when is_binary(out_dir) do
    compile_opts = compile_opts(opts)
    tier_metrics = TierMetrics.from_out_dir(out_dir, opts)
    tier_gate = TierGate.report(tier_metrics)
    stack = stack_indicators(out_dir)
    object_text = ObjectTextEstimate.estimate(out_dir, opts)
    linked = StackReport.read_linked_binary(Path.join(out_dir, "elmc_stack_report.json"))
    ram = ram_section(out_dir, compile_opts, stack, linked)
    flash = flash_section(tier_metrics, object_text, linked)
    constraint = classify_constraint(flash, ram, tier_gate)

    %{
      "contract" => @contract,
      "flash" => flash,
      "ram" => ram,
      "constraint" => Atom.to_string(constraint),
      "recommendation" => recommendation(constraint),
      "bytecode_tier" => wire_tier_gate(tier_gate),
      "bytecode_vm" => %{
        "enabled" => Elmc.Backend.Bytecode.BcVm.enabled?(compile_opts),
        "reason" => Elmc.Backend.Bytecode.BcVm.disabled_reason(compile_opts)
      }
    }
  end

  @spec write!(String.t(), keyword()) :: :ok
  def write!(out_dir, opts \\ []) when is_binary(out_dir) do
    report = build(out_dir, opts)

    out_dir
    |> Path.join(@report_name)
    |> then(&File.write(&1, Jason.encode!(report, pretty: true)))
    |> case do
      :ok -> :ok
      {:error, reason} -> raise "flash_vs_heap write failed: #{inspect(reason)}"
    end
  end

  @spec report_path(String.t()) :: String.t()
  def report_path(out_dir), do: Path.join(out_dir, @report_name)

  @spec classify_constraint(map(), map(), map()) :: constraint()
  def classify_constraint(flash, ram, tier_gate) do
    flash_share = Map.get(flash, "generated_text_share", 0.0)
    tier_eligible = Map.get(tier_gate, :eligible, false) == true

    heap_pressure? =
      Map.get(ram, "owned_slot_max", 0) >= @heap_owned_slot_threshold or
        Map.get(ram, "worker_last_dispatch_cmd_cap", 0) > 0 or
        not Map.get(ram, "native_worker_model", false)

    flash_pressure? =
      tier_eligible or
        (is_number(flash_share) and flash_share > @flash_share_threshold)

    cond do
      flash_pressure? and not heap_pressure? -> :flash_bound
      heap_pressure? and not flash_pressure? -> :heap_bound
      flash_pressure? and heap_pressure? -> :flash_bound
      true -> :balanced
    end
  end

  defp flash_section(tier_metrics, object_text, linked) do
    generated = Map.get(tier_metrics, :generated_text_bytes, 0)
    bin = Map.get(tier_metrics, :pebble_app_bin_bytes, 0)

    %{
      "generated_text_bytes" => generated,
      "pebble_app_bin_bytes" => bin,
      "generated_text_share" => if(bin > 0, do: generated / bin, else: 0.0),
      "elmc_app_text" => Map.get(object_text, "elmc_app_text"),
      "runtime_text" => Map.get(object_text, "runtime_text"),
      "linked_text" => get_in(linked, ["elf_size", "text"]),
      "large_rc_fn_count" =>
        tier_metrics
        |> Map.get(:rc_fn_text_sizes, [])
        |> Enum.count(fn {_name, bytes} -> bytes > Map.fetch!(TierGate.criteria(), :large_rc_fn_bytes) end)
    }
  end

  defp ram_section(out_dir, compile_opts, stack, linked) do
    %{
      "owned_slot_max" => Map.get(stack, "owned_slot_max", 0),
      "boxed_tmp_declarations" => Map.get(stack, "boxed_tmp_declarations", 0),
      "closure_allocations" => Map.get(stack, "closure_allocations", 0),
      "worker_last_dispatch_cmd_cap" => worker_last_dispatch_cmd_cap(compile_opts),
      "native_worker_model" => native_worker_model?(out_dir, compile_opts),
      "elf_bss" => get_in(linked, ["elf_size", "bss"]),
      "elf_data" => get_in(linked, ["elf_size", "data"])
    }
  end

  defp worker_last_dispatch_cmd_cap(compile_opts) do
    Elmc.Backend.Plan.Worker.Host.Lower.last_dispatch_cmd_cap_for_test(compile_opts)
  end

  defp native_worker_model?(out_dir, compile_opts) do
    worker_h = Path.join(out_dir, "c/elmc_worker.h")
    SizeProfile.size?(compile_opts) and File.regular?(worker_h) and
      File.read!(worker_h) =~ "ELMC_WORKER_NATIVE_MODEL"
  end

  defp recommendation(:flash_bound) do
    "Prefer size profile, fusion, and native emit before selective bytecode tier."
  end

  defp recommendation(:heap_bound) do
    "Prefer ModelNative, unboxed layouts, BSS caps, and shallower owned frames—not bytecode."
  end

  defp recommendation(:balanced) do
    "No dominant flash or RAM constraint from static metrics; keep monitoring heap after init/drain/view."
  end

  defp wire_tier_gate(tier_gate) do
    tier_gate
    |> Map.new(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
    |> Map.update("criteria", %{}, fn criteria ->
      case criteria do
        %{} = map ->
          Map.new(map, fn
            {k, v} when is_atom(k) -> {Atom.to_string(k), v}
            {k, v} -> {k, v}
          end)

        other ->
          other
      end
    end)
  end

  defp stack_indicators(out_dir) do
    path = Path.join(out_dir, "elmc_stack_report.json")

    with {:ok, contents} <- File.read(path),
         {:ok, %{"code_size_indicators" => indicators}} <- Jason.decode(contents),
         true <- is_map(indicators) do
      indicators
    else
      _ -> %{}
    end
  end

  defp compile_opts(opts) do
  opts
  |> Keyword.get(:compile_opts, %{})
  |> case do
    map when is_map(map) -> map
    _ -> Map.new(opts)
  end
  end
end
