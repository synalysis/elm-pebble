defmodule Elmc.Test.RcTrackHarness do
  @moduledoc false

  import ExUnit.Assertions, only: [assert: 2, flunk: 1]

  @runtime_link_stub Path.join(__DIR__, "elmc_runtime_link_stubs.c")

  @spec runtime_link_stub() :: String.t()
  def runtime_link_stub, do: @runtime_link_stub

  @type compile_opts :: keyword()

  @spec compile!(String.t(), String.t(), compile_opts()) :: :ok
  def compile!(project_dir, out_dir, opts \\ []) do
    compile_opts =
      Keyword.merge(
        [out_dir: out_dir, strip_dead_code: false, plan_ir_mode: :primary, plan_ir_strict: true],
        opts
      )

    case Elmc.compile(project_dir, compile_opts) do
      {:ok, _} -> :ok
      {:error, reason} -> flunk("compile failed: #{inspect(reason)}")
    end
  end

  @spec assert_no_elmc_unknown!(String.t()) :: :ok
  def assert_no_elmc_unknown!(out_dir) when is_binary(out_dir) do
    c_path = Path.join(out_dir, "c/elmc_generated.c")

    if File.regular?(c_path) do
      count =
        c_path
        |> File.read!()
        |> then(&Regex.scan(~r/elmc_unknown\b/, &1))
        |> length()

      if count != 0 do
        flunk("expected zero elmc_unknown in #{c_path}, got #{count}")
      end
    end

    :ok
  end

  @spec cc_flags(String.t(), keyword()) :: [String.t()]
  def cc_flags(out_dir, opts \\ []) do
    rc_track_flag = if Keyword.get(opts, :rc_track, true), do: ["-DELMC_RC_TRACK=1"], else: []

    alloc_track_flag =
      if Keyword.get(opts, :alloc_track, true), do: ["-DELMC_ALLOC_TRACK=1"], else: []

    alloc_probe_flag =
      if Keyword.get(opts, :alloc_probe, false), do: ["-DELMC_ALLOC_PROBE=1"], else: []

    [
      "-std=c11",
      "-Wall",
      "-Wextra"
    ] ++ rc_track_flag ++ alloc_track_flag ++ alloc_probe_flag ++ [
      "-include",
      Path.expand("elmc_host_stubs.h", __DIR__),
      "-I#{Path.join(out_dir, "runtime")}",
      "-I#{Path.join(out_dir, "ports")}",
      "-I#{Path.join(out_dir, "c")}"
    ] ++ Keyword.get(opts, :extra_flags, [])
  end

  @spec link_flags(keyword()) :: [String.t()]
  def link_flags(_opts \\ []), do: ["-lm"]

  @spec compile_and_link_args(String.t(), [String.t()], String.t(), keyword()) :: [String.t()]
  defp compile_and_link_args(out_dir, sources, binary_path, opts) do
    cc_flags(out_dir, opts) ++ with_runtime_link_stub(sources) ++ link_flags(opts) ++ ["-o", binary_path]
  end

  @spec with_runtime_link_stub([String.t()]) :: [String.t()]
  def with_runtime_link_stub(sources) do
    if Enum.any?(sources, &links_generated_c?/1), do: sources, else: sources ++ [@runtime_link_stub]
  end

  defp links_generated_c?(path) do
    cond do
      String.contains?(path, "elmc_generated.c") ->
        true

      String.ends_with?(path, "_harness.c") or String.ends_with?(path, "harness.c") ->
        case File.read(path) do
          {:ok, source} -> String.contains?(source, ~s/#include "elmc_generated.c"/)
          _ -> false
        end

      true ->
        false
    end
  end

  @spec compile_c(String.t(), [String.t()], String.t(), keyword()) :: {String.t(), non_neg_integer()}
  def compile_c(out_dir, sources, binary_path, opts \\ []) do
    cc = System.find_executable("cc") || flunk("cc not available for C harness compile")

    System.cmd(cc, compile_and_link_args(out_dir, sources, binary_path, opts))
  end

  @spec compile_c!(String.t(), [String.t()], String.t(), keyword()) :: :ok
  def compile_c!(out_dir, sources, binary_path, opts \\ []) do
    {compile_out, compile_code} = compile_c(out_dir, sources, binary_path, opts)
    if compile_code != 0, do: flunk("C compile failed:\n#{compile_out}")
    :ok
  end

  @spec run_harness!(String.t(), String.t(), String.t(), keyword()) :: String.t()
  def run_harness!(out_dir, harness_path, binary_name, opts \\ []) do
    {out, code} = run_harness_capture(out_dir, harness_path, binary_name, opts)
    if code != 0, do: flunk("rc track harness failed (exit #{code}):\n#{out}")
    out
  end

  @spec run_harness_capture(String.t(), String.t(), String.t(), keyword()) :: {String.t(), non_neg_integer()}
  def run_harness_capture(out_dir, harness_path, binary_name, opts \\ []) do
    cc = System.find_executable("cc") || flunk("cc not available for rc track harness")

    sources =
      Keyword.get_lazy(opts, :sources, fn ->
        [
          Path.join(out_dir, "runtime/elmc_runtime.c"),
          Path.join(out_dir, "ports/elmc_ports.c"),
          harness_path
        ]
      end)

    binary_path = Path.join(out_dir, binary_name)

    {compile_out, compile_code} =
      System.cmd(cc, compile_and_link_args(out_dir, sources, binary_path, opts))

    if compile_code != 0, do: flunk("harness compile failed:\n#{compile_out}")

    {run_out, run_code} = System.cmd(binary_path, [], stderr_to_stdout: true)

    {run_out, run_code}
  end

  @spec assert_balanced!(String.t()) :: :ok
  def assert_balanced!(run_out) do
    cond do
      String.contains?(run_out, "rc_ok") and not String.contains?(run_out, "rc leak") and
          not String.contains?(run_out, "malloc leak") ->
        :ok

      true ->
        flunk("expected balanced rc/alloc registry, got:\n#{run_out}")
    end
  end

  @spec parse_alloc_probe_update_rc_nets(String.t()) :: [{non_neg_integer(), non_neg_integer()}]
  def parse_alloc_probe_update_rc_nets(out) do
    Regex.scan(~r/probe move(\d+) update: rc_live \+\d+ rc_net \+(\d+)/, out)
    |> Enum.map(fn [_, move, net] -> {String.to_integer(move), String.to_integer(net)} end)
  end

  @spec parse_alloc_probe_view_leaks(String.t()) :: non_neg_integer()
  def parse_alloc_probe_view_leaks(out) do
    Regex.scan(~r/probe move\d+ view: rc_live \+\d+ rc_net \+\d+/, out)
    |> length()
  end

  @spec assert_alloc_probe_thresholds!(String.t(), keyword()) :: :ok
  def assert_alloc_probe_thresholds!(out, opts \\ []) do
    early_strict_moves = Keyword.get(opts, :early_strict_moves, 10)
    max_update_rc_net = Keyword.get(opts, :max_update_rc_net, 2)
    max_early_strict_leaks = Keyword.get(opts, :max_early_strict_leaks, 0)

    update_rc_nets = parse_alloc_probe_update_rc_nets(out)

    early_strict_leaks =
      Enum.count(update_rc_nets, fn {move, net} -> move < early_strict_moves and net != 0 end)

    catastrophic_update_leaks =
      Enum.count(update_rc_nets, fn {_move, net} -> net >= 10 end)

    max_net =
      case update_rc_nets do
        [] -> 0
        nets -> nets |> Enum.map(&elem(&1, 1)) |> Enum.max()
      end

    view_leaks = parse_alloc_probe_view_leaks(out)

    assert early_strict_leaks <= max_early_strict_leaks,
           "early-game update should be RC-balanced (moves 0-#{early_strict_moves - 1}); see probe output above"

    assert catastrophic_update_leaks == 0,
           "catastrophic fused native leak (rc_net >= 10 on an update move); see probe output above"

    assert max_net <= max_update_rc_net,
           "unexpected large per-move update rc_net (max +#{max_net}); see probe output above"

    assert view_leaks == 0,
           "unexpected view alloc leak (#{view_leaks} regions); see probe output above"

    :ok
  end

  @spec worker_sources(String.t()) :: [String.t()]
  def worker_sources(out_dir) do
    [
      Path.join(out_dir, "runtime/elmc_runtime.c"),
      Path.join(out_dir, "ports/elmc_ports.c"),
      Path.join(out_dir, "c/elmc_generated.c"),
      Path.join(out_dir, "c/elmc_pebble.c"),
      Path.join(out_dir, "c/elmc_worker.c")
    ]
  end

  @spec run_worker_harness!(String.t(), String.t(), String.t()) :: String.t()
  def run_worker_harness!(out_dir, harness_path, binary_name) do
    run_harness!(
      out_dir,
      harness_path,
      binary_name,
      sources: worker_sources(out_dir) ++ [harness_path]
    )
  end

  @type probe_spec :: %{
          name: String.t(),
          c_symbol: String.t(),
          release_result: boolean()
        }

  @doc """
  Build and run a host harness that checks ELMC_RC_TRACK balance for each probe.

  `module` is the Elm entry module (for example `"RcTrackListProbe"`).
  Each probe is a nullary generated function `elmc_fn_<Module>_<probe>`.
  """
  @spec list_int_length_c_helper() :: String.t()
  def list_int_length_c_helper do
    """
    static int list_int_length(ElmcValue *list) {
      if (list && list->tag == ELMC_TAG_INT_LIST) {
        ElmcValue *len = elmc_list_length(list);
        int value = len ? (int)elmc_as_int(len) : 0;
        if (len) elmc_release(len);
        return value;
      }
      int len = 0;
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        len += 1;
        cursor = ((ElmcCons *)cursor->payload)->tail;
      }
      return len;
    }
    """
  end

  @spec harness_rc_helpers() :: String.t()
  def harness_rc_helpers do
    """
    static ElmcValue *elmc_harness_new_int(elmc_int_t value) {
      ElmcValue *out = NULL;
      if (elmc_new_int(&out, value) != RC_SUCCESS) return elmc_int_zero();
      return out;
    }

    static ElmcValue *elmc_harness_list_from_int_array(const elmc_int_t *items, int count) {
      ElmcValue *out = NULL;
      if (elmc_list_from_int_array(&out, items, count) != RC_SUCCESS) return elmc_int_zero();
      return out;
    }

    static ElmcValue *elmc_harness_new_string(const char *value) {
      ElmcValue *out = NULL;
      if (elmc_new_string(&out, value) != RC_SUCCESS) return elmc_int_zero();
      return out;
    }

    static ElmcValue *elmc_harness_tuple2_take(ElmcValue *first, ElmcValue *second) {
      ElmcValue *out = NULL;
      if (elmc_tuple2_take(&out, first, second) != RC_SUCCESS) return elmc_int_zero();
      return out;
    }

    static ElmcValue *elmc_harness_result_ok(ElmcValue *value) {
      ElmcValue *out = NULL;
      if (elmc_result_ok(&out, value) != RC_SUCCESS) return elmc_int_zero();
      return out;
    }

    static ElmcValue *elmc_harness_result_err(ElmcValue *value) {
      ElmcValue *out = NULL;
      if (elmc_result_err(&out, value) != RC_SUCCESS) return elmc_int_zero();
      return out;
    }

    static ElmcValue *elmc_harness_maybe_just(ElmcValue *value) {
      ElmcValue *out = NULL;
      if (elmc_maybe_just(&out, value) != RC_SUCCESS) return elmc_int_zero();
      return out;
    }

    static ElmcValue *elmc_harness_closure_new(
        ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count),
        int arity) {
      ElmcValue *out = NULL;
      if (elmc_closure_new(&out, fn, arity, 0, NULL) != RC_SUCCESS) return elmc_int_zero();
      return out;
    }
    """
  end

  @spec harness_prelude() :: String.t()
  def harness_prelude do
    """
    #{harness_rc_helpers()}

    static ElmcValue *elmc_harness_call_value(
        ElmcValue *(*fn)(ElmcValue ** const args, const int argc),
        ElmcValue **args,
        int argc) {
      return fn(args, argc);
    }

    static ElmcValue *elmc_harness_call_rc(
        RC (*fn)(ElmcValue **out, ElmcValue ** const args, const int argc),
        ElmcValue **args,
        int argc) {
      ElmcValue *out = NULL;
      return fn(&out, args, argc) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static ElmcValue *elmc_harness_direct_rc_1_int(
        RC (*fn)(ElmcValue **out, elmc_int_t),
        elmc_int_t a0) {
      ElmcValue *out = NULL;
      return fn(&out, a0) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static ElmcValue *elmc_harness_direct_rc_1_box(
        RC (*fn)(ElmcValue **out, ElmcValue *),
        ElmcValue *a0) {
      ElmcValue *out = NULL;
      return fn(&out, a0) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static ElmcValue *elmc_harness_direct_rc_int_box(
        RC (*fn)(ElmcValue **out, elmc_int_t, ElmcValue *),
        elmc_int_t a0,
        ElmcValue *a1) {
      ElmcValue *out = NULL;
      return fn(&out, a0, a1) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static ElmcValue *elmc_harness_direct_rc_2_box(
        RC (*fn)(ElmcValue **out, ElmcValue *, ElmcValue *),
        ElmcValue *a0,
        ElmcValue *a1) {
      ElmcValue *out = NULL;
      return fn(&out, a0, a1) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static ElmcValue *elmc_harness_direct_rc_out_only(
        RC (*fn)(ElmcValue **out)) {
      ElmcValue *out = NULL;
      return fn(&out) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static ElmcValue *elmc_harness_direct_value_void(
        ElmcValue *(*fn)(void)) {
      return fn();
    }

    static ElmcValue *elmc_harness_direct_value_1_box(
        ElmcValue *(*fn)(ElmcValue *),
        ElmcValue *a0) {
      return fn(a0);
    }

    static ElmcValue *elmc_harness_direct_value_int_box(
        ElmcValue *(*fn)(elmc_int_t, ElmcValue *),
        elmc_int_t a0,
        ElmcValue *a1) {
      return fn(a0, a1);
    }

    static ElmcValue *elmc_harness_native_int_to_boxed(
        elmc_int_t (*fn)(ElmcValue *),
        ElmcValue *a0) {
      return elmc_harness_new_int(fn(a0));
    }
    """
  end

  @spec generated_fn_call(String.t(), String.t(), String.t(), String.t(), integer()) :: String.t()
  def generated_fn_call(out_dir, module_name, fn_name, args_expr, argc) do
    c_name = "elmc_fn_#{module_name}_#{fn_name}"

    case generated_fn_signature(out_dir, c_name) do
      {:rc, :argv} ->
        "elmc_harness_call_rc(#{c_name}, #{args_expr}, #{argc})"

      {:rc, [:boxed, :boxed], 2} ->
        "elmc_harness_direct_rc_2_box(#{c_name}, #{args_expr}[0], #{args_expr}[1])"

      {:rc, [:native_int], 1} ->
        "elmc_harness_direct_rc_1_int(#{c_name}, elmc_as_int(#{args_expr}[0]))"

      {:rc, [:boxed], 1} ->
        "elmc_harness_direct_rc_1_box(#{c_name}, #{args_expr}[0])"

      {:rc, [:native_int, :boxed], 2} ->
        "elmc_harness_direct_rc_int_box(#{c_name}, elmc_as_int(#{args_expr}[0]), #{args_expr}[1])"

      {:rc, [], 0} ->
        "elmc_harness_direct_rc_out_only(#{c_name})"

      {:value, [], 0} ->
        "elmc_harness_direct_value_void(#{c_name})"

      {:value, [:boxed], 1} ->
        "elmc_harness_direct_value_1_box(#{c_name}, #{args_expr}[0])"

      {:value, [:native_int, :boxed], 2} ->
        "elmc_harness_direct_value_int_box(#{c_name}, elmc_as_int(#{args_expr}[0]), #{args_expr}[1])"

      {:native_int, [:boxed], 1} ->
        "elmc_harness_native_int_to_boxed(#{c_name}, #{args_expr}[0])"

      _ ->
        "elmc_harness_call_value(#{c_name}, #{args_expr}, #{argc})"
    end
  end

  defp generated_fn_signature(out_dir, c_name) do
    generated_c_path = Path.join(out_dir, "c/elmc_generated.c")

    with {:ok, source} <- File.read(generated_c_path),
         {:ok, match} <- generated_fn_signature_match(source, c_name) do
      match
    else
      _ -> :unknown
    end
  end

  defp generated_fn_signature_match(source, c_name) do
    patterns = [
      {~r/(?:static\s+)?RC\s+#{Regex.escape(c_name)}\(ElmcValue \*\*out,\s*ElmcValue \*\* const args,\s*const int argc\)/,
       {:rc, :argv}},
      {~r/(?:static\s+)?RC\s+#{Regex.escape(c_name)}\(ElmcValue \*\*out,\s*ElmcValue \*\*args,\s*const int argc\)/,
       {:rc, :argv}},
      {~r/(?:static\s+)?RC\s+#{Regex.escape(c_name)}\(ElmcValue \*\*out,\s*ElmcValue \*\*args,\s*int argc\)/,
       {:rc, :argv}},
      {~r/(?:static\s+)?RC\s+#{Regex.escape(c_name)}\(ElmcValue \*\*out\)/, {:rc, [], 0}},
      {~r/(?:static\s+)?RC\s+#{Regex.escape(c_name)}\(ElmcValue \*\*out,\s*([^)]*)\)/, :rc_params},
      {~r/(?:static\s+)?ElmcValue \*\s*#{Regex.escape(c_name)}\(([^)]*)\)/, :value_params},
      {~r/(?:static\s+)?elmc_int_t\s+#{Regex.escape(c_name)}\(([^)]*)\)/, :native_int_params}
    ]

    Enum.find_value(patterns, fn
      {pattern, {:rc, :argv}} ->
        if Regex.match?(pattern, source), do: {:ok, {:rc, :argv}}

      {pattern, {:rc, [], 0}} ->
        if Regex.match?(pattern, source), do: {:ok, {:rc, [], 0}}

      {pattern, tag} ->
        case Regex.run(pattern, source) do
          [_, params] when tag in [:rc_params, :value_params, :native_int_params] ->
            kinds = parse_param_kinds(params)

            ret =
              case tag do
                :rc_params -> :rc
                :value_params -> :value
                :native_int_params -> :native_int
              end

            {:ok, {ret, kinds, length(kinds)}}

          [_, ""] ->
            ret =
              case tag do
                :rc_params -> :rc
                :value_params -> :value
                :native_int_params -> :native_int
              end

            {:ok, {ret, [], 0}}

          _ ->
            nil
        end

      _ ->
        nil
    end) || :error
  end

  defp parse_param_kinds(params) when is_binary(params) do
    params
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&direct_plan_param_kind/1)
    |> Enum.reject(&(&1 == :unknown))
  end

  defp parse_param_kinds(_), do: []

  defp direct_plan_param_kind("elmc_int_t" <> _), do: :native_int
  defp direct_plan_param_kind("bool" <> _), do: :native_bool
  defp direct_plan_param_kind("ElmcValue *" <> _), do: :boxed
  defp direct_plan_param_kind(_), do: :unknown

  @spec generated_fn_rc?(String.t(), String.t()) :: boolean()
  def generated_fn_rc?(out_dir, c_name) do
    generated_fn_full_rc?(out_dir, c_name) or generated_fn_out_only_rc?(out_dir, c_name)
  end

  @spec generated_fn_full_rc?(String.t(), String.t()) :: boolean()
  def generated_fn_full_rc?(out_dir, c_name) do
    generated_c_path = Path.join(out_dir, "c/elmc_generated.c")

    case File.read(generated_c_path) do
      {:ok, source} ->
        Enum.any?(
          [
            "RC #{c_name}(ElmcValue **out, ElmcValue ** const args",
            "static RC #{c_name}(ElmcValue **out, ElmcValue ** const args",
            "RC #{c_name}(ElmcValue **out, ElmcValue **args",
            "static RC #{c_name}(ElmcValue **out, ElmcValue **args"
          ],
          &String.contains?(source, &1)
        )

      _ ->
        false
    end
  end

  @spec generated_fn_out_only_rc?(String.t(), String.t()) :: boolean()
  def generated_fn_out_only_rc?(out_dir, c_name) do
    generated_c_path = Path.join(out_dir, "c/elmc_generated.c")

    case File.read(generated_c_path) do
      {:ok, source} ->
        Enum.any?(
          [
            "RC #{c_name}(ElmcValue **out)",
            "static RC #{c_name}(ElmcValue **out)"
          ],
          &String.contains?(source, &1)
        )

      _ ->
        false
    end
  end

  @spec generated_fn_native_rc?(String.t(), String.t()) :: boolean()
  def generated_fn_native_rc?(out_dir, c_name) do
    native = "#{c_name}_native"
    generated_c_path = Path.join(out_dir, "c/elmc_generated.c")

    case File.read(generated_c_path) do
      {:ok, source} ->
        Enum.any?(
          [
            "RC #{native}(elmc_int_t *out)",
            "static RC #{native}(elmc_int_t *out)"
          ],
          &String.contains?(source, &1)
        )

      _ ->
        false
    end
  end

  @spec generated_fn_native_int_void?(String.t(), String.t()) :: boolean()
  def generated_fn_native_int_void?(out_dir, c_name) do
    generated_c_path = Path.join(out_dir, "c/elmc_generated.c")

    case File.read(generated_c_path) do
      {:ok, source} ->
        Enum.any?(
          [
            "elmc_int_t #{c_name}(void)",
            "static elmc_int_t #{c_name}(void)"
          ],
          &String.contains?(source, &1)
        )

      _ ->
        false
    end
  end

  @spec generated_fn_scalar_int_rc?(String.t(), String.t()) :: boolean()
  def generated_fn_scalar_int_rc?(out_dir, c_name) do
    generated_c_path = Path.join(out_dir, "c/elmc_generated.c")

    case File.read(generated_c_path) do
      {:ok, source} ->
        Enum.any?(
          [
            "RC #{c_name}(elmc_int_t *out)",
            "static RC #{c_name}(elmc_int_t *out)"
          ],
          &String.contains?(source, &1)
        )

      _ ->
        false
    end
  end

  defp scalar_int_probe_thunk(symbol, c_name) do
    """
    static ElmcValue *#{symbol}_probe(void) {
      elmc_int_t value = 0;
      if (#{c_name}(&value) != RC_SUCCESS) return elmc_int_zero();
      ElmcValue *out = NULL;
      if (elmc_new_int(&out, value) != RC_SUCCESS) return elmc_int_zero();
      return out;
    }
    """
  end

  @spec generated_fn_value_void?(String.t(), String.t()) :: boolean()
  def generated_fn_value_void?(out_dir, c_name) do
    generated_c_path = Path.join(out_dir, "c/elmc_generated.c")

    case File.read(generated_c_path) do
      {:ok, source} ->
        Enum.any?(
          [
            "ElmcValue * #{c_name}(void)",
            "ElmcValue *#{c_name}(void)",
            "static ElmcValue * #{c_name}(void)",
            "static ElmcValue *#{c_name}(void)"
          ],
          &String.contains?(source, &1)
        )

      _ ->
        false
    end
  end

  @spec run_probe_suite!(String.t(), String.t(), String.t(), [probe_spec()]) :: String.t()
  def run_probe_suite!(out_dir, module_name, binary_name, probes) do
    harness_path = Path.join(out_dir, "c/#{binary_name}_harness.c")
    probe_cases = Enum.map_join(probes, "\n", &probe_case_c/1)

    File.write!(
      harness_path,
      """
      #include "elmc_generated.h"
      #include "elmc_generated.c"
      #include <stdio.h>

      #{harness_prelude()}

      static int run_probe(const char *name, ElmcValue *(*fn)(void), int release_result) {
        elmc_rc_track_reset();
      #if ELMC_ALLOC_TRACK
        elmc_alloc_track_reset();
      #endif
        ElmcValue *out = fn();
        if (release_result && out) elmc_release(out);
        elmc_process_release_all_slots();
        if (!elmc_rc_track_check_balanced()) {
          fprintf(stderr, "rc leak in %s\\n", name);
          return 1;
        }
      #if ELMC_ALLOC_TRACK
        if (!elmc_alloc_track_check_balanced()) {
          fprintf(stderr, "malloc leak in %s\\n", name);
          return 1;
        }
      #endif
        return 0;
      }

      #{probe_thunks(out_dir, module_name, probes)}

      int main(void) {
      #{probe_cases}
        printf("rc_ok #{module_name} probes=%d\\n", #{length(probes)});
        return 0;
      }
      """
    )

    run_harness!(out_dir, harness_path, binary_name)
  end

  @spec int_probes([String.t()]) :: [probe_spec()]
  def int_probes(names) do
    Enum.map(names, fn name ->
      %{name: name, c_symbol: name, release_result: true}
    end)
  end

  @spec list_probes([String.t()]) :: [probe_spec()]
  def list_probes(names) do
    Enum.map(names, fn name ->
      %{name: name, c_symbol: name, release_result: true}
    end)
  end

  @doc """
  Run each probe `iterations` times with a fresh RC registry per iteration.
  """
  @spec run_stress_suite!(String.t(), String.t(), String.t(), [probe_spec()], pos_integer()) ::
          String.t()
  def run_stress_suite!(out_dir, module_name, binary_name, probes, iterations) do
    harness_path = Path.join(out_dir, "c/#{binary_name}_harness.c")
    probe_cases = Enum.map_join(probes, "\n", &stress_probe_case_c(&1, iterations))

    File.write!(
      harness_path,
      """
      #include "elmc_generated.h"
      #include "elmc_generated.c"
      #include <stdio.h>

      #{harness_prelude()}

      static int run_probe_iterations(
          const char *name,
          ElmcValue *(*fn)(void),
          int release_result,
          int iterations) {
        for (int i = 0; i < iterations; i++) {
          elmc_rc_track_reset();
          ElmcValue *out = fn();
          if (release_result && out) elmc_release(out);
          elmc_process_release_all_slots();
          if (!elmc_rc_track_check_balanced()) {
            fprintf(stderr, "rc leak in %s at iteration %d\\n", name, i);
            return 1;
          }
        }
        return 0;
      }

      #{probe_thunks(out_dir, module_name, probes)}

      int main(void) {
      #{probe_cases}
        printf("rc_ok #{module_name} stress probes=%d iterations=#{iterations}\\n", #{length(probes)});
        return 0;
      }
      """
    )

    run_harness!(out_dir, harness_path, binary_name)
  end

  @spec run_stress_core_probe!(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          pos_integer()
        ) :: String.t()
  def run_stress_core_probe!(test_dir, fixture_dir, module_name, probe_name, binary_name, iterations) do
    project_dir = Path.expand(fixture_dir, test_dir)
    out_dir = Path.expand("tmp/#{binary_name}", test_dir)
    File.rm_rf!(out_dir)
    compile!(project_dir, out_dir, entry_module: module_name)

    run_stress_suite!(
      out_dir,
      module_name,
      binary_name,
      int_probes([probe_name]),
      iterations
    )
  end

  defp stress_probe_case_c(%{name: name, c_symbol: symbol, release_result: release_result}, iterations) do
    release = if release_result, do: "1", else: "0"

    """
        if (run_probe_iterations("#{name}", #{symbol}_probe, #{release}, #{iterations}) != 0) return 1;
    """
  end

  defp probe_thunks(out_dir, module_name, probes) do
    Enum.map_join(probes, "\n", fn %{c_symbol: symbol} ->
      c_name = "elmc_fn_#{module_name}_#{symbol}"
      probe_thunk_body(out_dir, symbol, c_name)
    end)
  end

  defp probe_thunk_body(out_dir, symbol, c_name) do
    case generated_fn_signature(out_dir, c_name) do
      {:rc, :argv} ->
        """
        static ElmcValue *#{symbol}_probe(void) {
          return elmc_harness_call_rc(#{c_name}, NULL, 0);
        }
        """

      {:rc, [], 0} ->
        """
        static ElmcValue *#{symbol}_probe(void) {
          return elmc_harness_direct_rc_out_only(#{c_name});
        }
        """

      {:value, [], 0} ->
        """
        static ElmcValue *#{symbol}_probe(void) {
          return #{c_name}();
        }
        """

      _ ->
        legacy_probe_thunk_body(out_dir, symbol, c_name)
    end
  end

  defp legacy_probe_thunk_body(out_dir, symbol, c_name) do
    cond do
      generated_fn_native_rc?(out_dir, c_name) ->
        scalar_int_probe_thunk(symbol, "#{c_name}_native")

      generated_fn_native_int_void?(out_dir, c_name) ->
        """
        static ElmcValue *#{symbol}_probe(void) {
          elmc_int_t value = #{c_name}();
          ElmcValue *out = NULL;
          if (elmc_new_int(&out, value) != RC_SUCCESS) return elmc_int_zero();
          return out;
        }
        """

      generated_fn_scalar_int_rc?(out_dir, c_name) ->
        scalar_int_probe_thunk(symbol, c_name)

      generated_fn_out_only_rc?(out_dir, c_name) ->
        """
        static ElmcValue *#{symbol}_probe(void) {
          ElmcValue *out = NULL;
          if (#{c_name}(&out) != RC_SUCCESS) return elmc_int_zero();
          return out;
        }
        """

      generated_fn_full_rc?(out_dir, c_name) ->
        """
        static ElmcValue *#{symbol}_probe(void) {
          return elmc_harness_call_rc(#{c_name}, NULL, 0);
        }
        """

      generated_fn_value_void?(out_dir, c_name) ->
        """
        static ElmcValue *#{symbol}_probe(void) {
          return #{c_name}();
        }
        """

      true ->
        """
        static ElmcValue *#{symbol}_probe(void) {
          return elmc_harness_call_value(#{c_name}, NULL, 0);
        }
        """
    end
  end

  defp probe_case_c(%{name: name, c_symbol: symbol, release_result: release_result}) do
    release = if release_result, do: "1", else: "0"

    """
        if (run_probe("#{name}", #{symbol}_probe, #{release}) != 0) return 1;
    """
  end
end
