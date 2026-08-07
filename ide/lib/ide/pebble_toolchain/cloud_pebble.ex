defmodule Ide.PebbleToolchain.CloudPebble do
  @moduledoc false

  alias Ide.PebbleToolchain.Command
  alias Ide.PebbleToolchain.Types

  @type project_slug :: Types.project_slug()
  @type opts :: Types.opts()
  @type command_result :: Types.command_result()
  @type toolchain_error :: Types.toolchain_error()

  @default_install_timeout_seconds 120

  @doc """
  Installs a `.pbw` to a paired watch via CloudPebble Dev Connect (`pebble install --cloudpebble`).

  Firebase credentials are staged in an isolated temporary home directory so hosted IDE
  deployments never write into the host user's Pebble SDK oauth storage.
  """
  @spec install_cloudpebble(project_slug(), opts()) ::
          {:ok, command_result()} | {:error, toolchain_error()}
  def install_cloudpebble(_project_slug, opts) do
    with {:ok, firebase_id_token} <- normalize_firebase_token(Keyword.get(opts, :firebase_id_token)),
         {:ok, package_path} <- normalize_package_path(Keyword.get(opts, :package_path)),
         {:ok, credential_home} <- create_credential_home() do
      try do
        :ok = write_firebase_credentials!(credential_home, firebase_id_token)

        timeout_seconds =
          max(Keyword.get(opts, :install_timeout_seconds, @default_install_timeout_seconds), 30)

        cwd = Path.dirname(package_path)
        env = credential_env(credential_home)

        Command.run_pebble_with_timeout(
          ["install", "--cloudpebble", package_path],
          timeout_seconds,
          cwd: cwd,
          env: env
        )
      after
        File.rm_rf(credential_home)
      end
    end
  end

  @spec normalize_package_path(term()) :: {:ok, String.t()} | {:error, toolchain_error()}
  defp normalize_package_path(path) when is_binary(path) do
    expanded = Path.expand(path)

    cond do
      String.trim(expanded) == "" ->
        {:error, :pbw_not_found}

      File.regular?(expanded) ->
        {:ok, expanded}

      true ->
        {:error, :pbw_not_found}
    end
  end

  defp normalize_package_path(_), do: {:error, :pbw_not_found}

  @spec normalize_firebase_token(term()) :: {:ok, String.t()} | {:error, toolchain_error()}
  defp normalize_firebase_token(token) when is_binary(token) do
    trimmed = String.trim(token)

    if trimmed == "" do
      {:error, :firebase_id_token_required}
    else
      {:ok, trimmed}
    end
  end

  defp normalize_firebase_token(_), do: {:error, :firebase_id_token_required}

  @spec create_credential_home() :: {:ok, String.t()} | {:error, toolchain_error()}
  defp create_credential_home do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_cloudpebble_credentials_#{System.unique_integer([:positive])}"
      )

    case File.mkdir_p(root) do
      :ok -> {:ok, root}
      {:error, reason} -> {:error, {:credential_home_failed, reason}}
    end
  end

  @spec write_firebase_credentials!(String.t(), String.t()) :: :ok
  defp write_firebase_credentials!(credential_home, firebase_id_token) do
    payload = Jason.encode!(%{"id_token" => firebase_id_token})

    for oauth_dir <- oauth_firebase_dirs(credential_home) do
      File.mkdir_p!(oauth_dir)
      File.write!(Path.join(oauth_dir, "firebase_oauth_storage.json"), payload)
    end

    :ok
  end

  @spec oauth_firebase_dirs(String.t()) :: [String.t()]
  defp oauth_firebase_dirs(credential_home) do
    case :os.type() do
      {:unix, :darwin} ->
        [
          Path.join([
            credential_home,
            "Library",
            "Application Support",
            "Pebble SDK",
            "oauth_firebase"
          ])
        ]

      _ ->
        xdg_data_home = Path.join(credential_home, ".local/share")

        [
          Path.join([xdg_data_home, "pebble-sdk", "oauth_firebase"]),
          Path.join([credential_home, ".pebble-sdk", "oauth_firebase"])
        ]
    end
  end

  @spec credential_env(String.t()) :: [{String.t(), String.t()}]
  defp credential_env(credential_home) do
    xdg_data_home = Path.join(credential_home, ".local/share")

    [
      {"HOME", credential_home},
      {"XDG_DATA_HOME", xdg_data_home}
    ]
  end
end
