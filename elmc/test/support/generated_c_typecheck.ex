defmodule Elmc.TestSupport.GeneratedCTypecheck do
  @moduledoc """
  Host `cc` typecheck for generated `elmc_generated.c`.

  The plan strict gate only runs Elixir→C codegen. Pebble SDK builds additionally
  compile that C with `-Werror=int-conversion`. This helper closes that gap without
  a full PBW/waf cycle.

  Successful typechecks are cached by generated-C content hash (+ host stubs and
  compiler identity) under the test compile cache root so warm plan-strict runs
  skip repeated `cc -fsyntax-only`.
  """

  alias Elmc.TestSupport.CompileCache

  @host_stubs Path.expand("elmc_host_stubs.h", __DIR__)
  # Bump when cc flags / include contract changes.
  @cc_flags_version 4

  @spec assert_typechecks!(String.t()) :: :ok
  def assert_typechecks!(out_dir) when is_binary(out_dir) do
    cc =
      System.find_executable("cc") ||
        raise("cc not available for generated C typecheck")

    generated = Path.join(out_dir, "c/elmc_generated.c")
    runtime_h_dir = Path.join(out_dir, "runtime")
    ports_dir = Path.join(out_dir, "ports")
    c_dir = Path.join(out_dir, "c")

    unless File.regular?(generated), do: raise("missing #{generated}")

    case cached_ok?(generated) do
      true ->
        :ok

      false ->
        {out, code} =
          System.cmd(
            cc,
            [
              "-std=c11",
              "-fsyntax-only",
              "-Wall",
              # Tangram-class bug: elmc_as_int(elmc_int_t). GCC 16 also hard-errors
              # some pointer ABI mismatches; keep those as warnings until call/callee
              # native-out vs boxed-out is fully unified (see companion encodeColorCode).
              "-Werror=int-conversion",
              "-Werror=implicit-function-declaration",
              "-Wno-error=incompatible-pointer-types",
              "-include",
              @host_stubs,
              "-I#{runtime_h_dir}",
              "-I#{ports_dir}",
              "-I#{c_dir}",
              generated
            ],
            stderr_to_stdout: true
          )

        if code != 0 do
          raise("generated C typecheck failed (exit #{code}):\n#{out}")
        end

        remember_ok!(generated)
        :ok
    end
  end

  defp cached_ok?(generated) do
    path = marker_path(generated)
    File.regular?(path)
  end

  defp remember_ok!(generated) do
    path = marker_path(generated)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "")
    :ok
  rescue
    _ -> :ok
  end

  defp marker_path(generated) do
    key =
      CompileCache.key({
        :generated_c_typecheck_v1,
        @cc_flags_version,
        CompileCache.file_hash(generated),
        CompileCache.file_hash(@host_stubs),
        CompileCache.compiler_identity()
      })

    Path.join([CompileCache.cache_root(), "cc-typecheck", key <> ".ok"])
  end
end
