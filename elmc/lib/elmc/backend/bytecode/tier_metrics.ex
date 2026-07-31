defmodule Elmc.Backend.Bytecode.TierMetrics do
  @moduledoc false

  alias Elmc.Backend.Bytecode.TierGate
  alias Elmc.Backend.CCodegen.{ObjectTextEstimate, StackReport}

  @type t :: %{
          optional(:generated_text_bytes) => non_neg_integer(),
          optional(:pebble_app_bin_bytes) => non_neg_integer(),
          optional(:rc_fn_text_sizes) => [{String.t(), non_neg_integer()}]
        }

  @rc_fn_re ~r/static RC (elmc_fn_[A-Za-z0-9_]+)\([^{]*\{([\s\S]*?)\n\}/

  @spec from_out_dir(String.t(), keyword()) :: t()
  def from_out_dir(out_dir, opts \\ []) when is_binary(out_dir) do
    generated_source = generated_c_source(out_dir)
    object_text = ObjectTextEstimate.estimate(out_dir, opts)
    stack = stack_indicators(out_dir)

    generated_text_bytes =
      object_text
      |> Map.get("generated_text")
      |> or_else(fn -> Map.get(stack, "generated_c_bytes") end)
      |> or_else(fn -> if is_binary(generated_source), do: byte_size(generated_source), else: nil end)

    pebble_app_bin_bytes =
      Keyword.get(opts, :pebble_app_bin_bytes) ||
        linked_elf_size(out_dir) ||
        linked_elf_size_from_opts(opts)

    %{
      generated_text_bytes: generated_text_bytes || 0,
      pebble_app_bin_bytes: pebble_app_bin_bytes || 0,
      rc_fn_text_sizes: rc_fn_text_sizes(generated_source)
    }
  end

  @spec report(String.t(), keyword()) :: map()
  def report(out_dir, opts \\ []) when is_binary(out_dir) do
    metrics = from_out_dir(out_dir, opts)

    TierGate.report(metrics)
    |> Map.put(:metrics, metrics)
  end

  @spec eligible?(String.t(), keyword()) :: boolean()
  def eligible?(out_dir, opts \\ []) when is_binary(out_dir) do
    out_dir
    |> from_out_dir(opts)
    |> TierGate.eligible?()
  end

  @spec rc_fn_text_sizes(String.t() | nil) :: [{String.t(), non_neg_integer()}]
  def rc_fn_text_sizes(nil), do: []

  def rc_fn_text_sizes(source) when is_binary(source) do
    @rc_fn_re
    |> Regex.scan(source)
    |> Enum.map(fn [_match, name, body] -> {name, byte_size(body)} end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  defp generated_c_source(out_dir) do
    path = Path.join(out_dir, "c/elmc_generated.c")

    case File.read(path) do
      {:ok, source} -> source
      _ -> nil
    end
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

  defp linked_elf_size(out_dir) do
    case StackReport.read_linked_binary(Path.join(out_dir, "elmc_stack_report.json")) do
      %{"elf_size" => %{"file_bytes" => bytes}} when is_integer(bytes) -> bytes
      %{"elf_size" => %{"dec" => bytes}} when is_integer(bytes) -> bytes
      _ -> nil
    end
  end

  defp linked_elf_size_from_opts(opts) do
    Keyword.get(opts, :linked_elf_size)
  end

  defp or_else(nil, fun), do: fun.()
  defp or_else(value, _fun), do: value
end
