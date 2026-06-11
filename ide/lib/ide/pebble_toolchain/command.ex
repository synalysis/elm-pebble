defmodule Ide.PebbleToolchain.Command do
  @moduledoc false

  alias Ide.Paths
  alias Ide.PebbleToolchain.Types

  @type command_result :: Types.command_result()
  @type pebble_opts :: Types.pebble_opts()
  @type toolchain_error :: Types.toolchain_error()

  @spec run_pebble([String.t()], pebble_opts()) ::
          {:ok, command_result()} | {:error, toolchain_error()}
  def run_pebble(args, opts) do
    with {:ok, pebble_bin} <- pebble_bin(),
         {:ok, cwd} <- command_cwd(opts) do
      env = pebble_command_env(args, opts)

      {output, exit_code} =
        System.cmd(pebble_bin, args, cd: cwd, stderr_to_stdout: true, env: env)

      {:ok,
       %{
         status: if(exit_code == 0, do: :ok, else: :error),
         command: Enum.join([pebble_bin | args], " "),
         output: output,
         exit_code: exit_code,
         cwd: cwd
       }}
    end
  rescue
    error -> {:error, error}
  end

  @spec run_pebble_with_timeout([String.t()], pos_integer(), pebble_opts()) ::
          {:ok, command_result()} | {:error, toolchain_error()}
  def run_pebble_with_timeout(args, timeout_seconds, opts)
      when is_list(args) and is_integer(timeout_seconds) and timeout_seconds > 0 do
    with {:ok, pebble_bin} <- pebble_bin(),
         {:ok, cwd} <- command_cwd(opts) do
      env = pebble_command_env(args, opts)
      timeout_bin = System.find_executable("timeout")

      if is_binary(timeout_bin) and timeout_bin != "" do
        cmd_args = ["#{timeout_seconds}s", pebble_bin] ++ args

        {output, exit_code} =
          System.cmd(timeout_bin, cmd_args, cd: cwd, stderr_to_stdout: true, env: env)

        {:ok,
         %{
           status: if(exit_code == 0, do: :ok, else: :error),
           command: Enum.join([timeout_bin | cmd_args], " "),
           output: output,
           exit_code: exit_code,
           cwd: cwd
         }}
      else
        run_pebble(args, opts)
      end
    end
  rescue
    error -> {:error, error}
  end

  @spec pebble_command_env([String.t()], keyword()) :: [{String.t(), String.t()}]
  def pebble_command_env(args, opts \\ []) do
    env = [{"LC_ALL", "C"}] ++ Keyword.get(opts, :env, [])

    if pebble_emulator_command?(args) do
      maybe_prepend_linux_bzip2_compat_path(env)
    else
      env
    end
  end

  @spec build_env(keyword()) :: [{String.t(), String.t()}]
  def build_env(opts) do
    []
    |> maybe_build_env_flag(opts, :emulator_storage_logs, "ELMC_PEBBLE_EMULATOR_STORAGE_LOGS")
    |> maybe_build_env_agent_probes(opts)
    |> maybe_build_env_watchface(opts)
  end

  @spec pebble_bin() :: {:ok, String.t()} | {:error, :pebble_cli_not_found}
  def pebble_bin do
    cond do
      configured = Application.get_env(:ide, Ide.PebbleToolchain, []) |> Keyword.get(:pebble_bin) ->
        {:ok, configured}

      resolved = System.find_executable("pebble") ->
        {:ok, resolved}

      true ->
        {:error, :pebble_cli_not_found}
    end
  end

  @spec elm_bin() :: {:ok, String.t()} | {:error, :elm_compiler_not_found}
  def elm_bin do
    configured =
      Application.get_env(:ide, Ide.PebbleToolchain, [])
      |> Keyword.get(:elm_bin)

    env_bin = System.get_env("ELM_BIN")

    [
      configured,
      env_bin,
      System.find_executable("elm"),
      Path.expand("../../../elm_pebble_dev/node_modules/.bin/elm", __DIR__)
    ]
    |> Enum.find_value(fn
      path when is_binary(path) and path != "" ->
        expanded = Path.expand(path)
        if File.exists?(expanded), do: {:ok, expanded}

      _ ->
        nil
    end) || {:error, :elm_compiler_not_found}
  end

  @spec template_app_root() :: {:ok, String.t()} | {:error, :template_app_root_not_found}
  def template_app_root do
    configured =
      Application.get_env(:ide, Ide.PebbleToolchain, [])
      |> Keyword.get(:template_app_root)

    candidates = [
      Paths.priv_path("pebble_app_template"),
      configured
    ]

    case Enum.find(candidates, &(is_binary(&1) and &1 != "" and File.dir?(&1))) do
      path when is_binary(path) -> {:ok, Path.expand(path)}
      _ -> {:error, :template_app_root_not_found}
    end
  end

  @spec command_cwd(pebble_opts()) :: {:ok, String.t()} | {:error, toolchain_error()}
  defp command_cwd(opts) do
    case Keyword.get(opts, :cwd) do
      cwd when is_binary(cwd) and cwd != "" ->
        if File.dir?(cwd), do: {:ok, cwd}, else: template_app_root()

      _ ->
        template_app_root()
    end
  end

  defp maybe_build_env_flag(env, opts, key, name) do
    if Keyword.get(opts, key, false), do: [{name, "1"} | env], else: env
  end

  # Always pin agent probes for Pebble builds. A leaked ELMC_AGENT_PROBES=1 in the
  # parent shell (for example from local bisect scripts) must not ship in emulator PBWs.
  defp maybe_build_env_agent_probes(env, opts) do
    value = if Keyword.get(opts, :emulator_agent_probes, false), do: "1", else: "0"
    [{"ELMC_AGENT_PROBES", value} | env]
  end

  defp maybe_build_env_watchface(env, opts) do
    if Keyword.get(opts, :target_type) == "watchface",
      do: [{"ELMC_WATCHFACE_MODE", "1"} | env],
      else: env
  end

  @spec pebble_emulator_command?([String.t()]) :: boolean()
  defp pebble_emulator_command?(["wipe" | _]), do: true
  defp pebble_emulator_command?(args), do: Enum.member?(args, "--emulator")

  @spec maybe_prepend_linux_bzip2_compat_path([{String.t(), String.t()}]) :: [
          {String.t(), String.t()}
        ]
  defp maybe_prepend_linux_bzip2_compat_path(env) do
    case ensure_linux_bzip2_compat_dir() do
      {:ok, dir} -> prepend_env_path(env, "LD_LIBRARY_PATH", dir)
      _ -> env
    end
  end

  @spec ensure_linux_bzip2_compat_dir() ::
          {:ok, String.t()} | {:error, toolchain_error()} | :ignore
  defp ensure_linux_bzip2_compat_dir do
    cond do
      :os.type() != {:unix, :linux} ->
        :ignore

      Enum.any?(legacy_bzip2_candidates(), &File.exists?/1) ->
        :ignore

      true ->
        with {:ok, source} <- first_existing_path(bzip2_soname_alias_candidates()),
             {:ok, dir} <- pebble_toolchain_compat_dir(),
             :ok <- File.mkdir_p(dir),
             :ok <- ensure_symlink(Path.join(dir, "libbz2.so.1.0"), source) do
          {:ok, dir}
        end
    end
  end

  @spec ensure_symlink(String.t(), String.t()) :: :ok | {:error, toolchain_error()}
  defp ensure_symlink(link_path, target_path) do
    case File.ln_s(target_path, link_path) do
      :ok ->
        :ok

      {:error, :eexist} ->
        if File.exists?(link_path) do
          :ok
        else
          with :ok <- File.rm(link_path), do: File.ln_s(target_path, link_path)
        end

      error ->
        error
    end
  end

  @spec prepend_env_path([{String.t(), String.t()}], String.t(), String.t()) :: [
          {String.t(), String.t()}
        ]
  defp prepend_env_path(env, key, path) do
    {existing_entries, rest} = Enum.split_with(env, fn {env_key, _value} -> env_key == key end)

    existing =
      case List.last(existing_entries) do
        {_key, value} -> value
        nil -> System.get_env(key)
      end

    value =
      [path, existing]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(":")

    [{key, value} | rest]
  end

  @spec first_existing_path([String.t()]) :: {:ok, String.t()} | {:error, :not_found}
  defp first_existing_path(paths) do
    case Enum.find(paths, &File.exists?/1) do
      nil -> {:error, :not_found}
      path -> {:ok, path}
    end
  end

  @spec pebble_toolchain_compat_dir() :: {:ok, String.t()} | {:error, toolchain_error()}
  defp pebble_toolchain_compat_dir do
    configured =
      Application.get_env(:ide, Ide.PebbleToolchain, [])
      |> Keyword.get(:pebble_toolchain_compat_dir)

    cond do
      is_binary(configured) and configured != "" ->
        {:ok, configured}

      cache_home = System.get_env("XDG_CACHE_HOME") ->
        {:ok, Path.join([cache_home, "elm-pebble", "pebble-toolchain-compat"])}

      true ->
        {:ok, Path.join([System.user_home!(), ".cache", "elm-pebble", "pebble-toolchain-compat"])}
    end
  rescue
    error -> {:error, error}
  end

  @spec legacy_bzip2_candidates() :: [String.t()]
  defp legacy_bzip2_candidates do
    configured =
      Application.get_env(:ide, Ide.PebbleToolchain, [])
      |> Keyword.get(:legacy_bzip2_candidates)

    if is_list(configured) do
      configured
    else
      [
        "/lib64/libbz2.so.1.0",
        "/usr/lib64/libbz2.so.1.0",
        "/lib/x86_64-linux-gnu/libbz2.so.1.0",
        "/usr/lib/x86_64-linux-gnu/libbz2.so.1.0"
      ]
    end
  end

  @spec bzip2_soname_alias_candidates() :: [String.t()]
  defp bzip2_soname_alias_candidates do
    configured =
      Application.get_env(:ide, Ide.PebbleToolchain, [])
      |> Keyword.get(:bzip2_soname_alias_candidates)

    if is_list(configured) do
      configured
    else
      [
        "/lib64/libbz2.so.1",
        "/usr/lib64/libbz2.so.1",
        "/lib/x86_64-linux-gnu/libbz2.so.1",
        "/usr/lib/x86_64-linux-gnu/libbz2.so.1"
      ]
    end
  end
end
