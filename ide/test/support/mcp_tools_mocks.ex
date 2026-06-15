defmodule Ide.TestSupport.McpToolsMocks do
  @moduledoc false

  defmodule MockCompiler do
    @moduledoc false
    alias Ide.Compiler.ManifestCache

    def check(_slug, _opts),
      do: {:ok, %{status: :ok, checked_path: ".", diagnostics: [], output: "ok"}}

    def check_source_root(_slug, opts),
      do:
        {:ok,
         %{
           status: :ok,
           checked_path: opts[:source_root] || ".",
           diagnostics: [],
           output: "ok"
         }}

    def compile(_slug, _opts),
      do:
        {:ok,
         %{
           status: :ok,
           compiled_path: ".",
           revision: "mock-rev",
           cached?: false,
           diagnostics: [],
           output: "ok"
         }}

    def manifest(slug, opts) do
      strict? = Keyword.get(opts, :strict, false)
      revision = "mock-rev:strict=#{strict?}"

      result = %{
        status: :ok,
        diagnostics: [],
        output: "ok",
        manifest_path: ".",
        revision: revision,
        cached?: false,
        strict?: strict?,
        manifest: %{
          schema_version: 1,
          supported_packages: ["elm/core"],
          excluded_packages: [],
          modules_detected: ["Main"]
        }
      }

      :ok = ManifestCache.put(slug, revision, result)
      {:ok, result}
    end
  end

  defmodule StructuredWarningCompiler do
    @moduledoc false
    alias Ide.TestSupport.McpToolsMocks.MockCompiler

    def check(_slug, _opts) do
      {:ok,
       %{
         status: :ok,
         checked_path: ".",
         diagnostics: [
           %{
             severity: "warning",
             source: "elmc/lowerer/pattern",
             message: "Constructor Wrap expects payload pattern",
             file: nil,
             line: 12,
             column: nil,
             warning_type: "lowerer-warning",
             warning_code: "constructor_payload_arity",
             warning_constructor: "Wrap",
             warning_expected_kind: "single",
             warning_has_arg_pattern: false
           }
         ],
         output: "ok"
       }}
    end

    def compile(_slug, _opts), do: MockCompiler.compile(nil, [])
    def manifest(slug, opts), do: MockCompiler.manifest(slug, opts)
  end

  defmodule MockPackageProvider do
    @moduledoc false
    @behaviour Ide.Packages.Provider

    @impl true
    def search(_query, _opts) do
      {:ok, [%{name: "elm/http", summary: "HTTP", license: "BSD-3-Clause", version: "2.0.0"}]}
    end

    @impl true
    def package_details(package, _opts) do
      {:ok,
       %{
         name: package,
         summary: "HTTP",
         license: "BSD-3-Clause",
         latest_version: "2.0.0",
         versions: ["1.0.0", "2.0.0"],
         exposed_modules: ["Http"],
         elm_json: %{}
       }}
    end

    @impl true
    def versions("elm/http", _opts), do: {:ok, ["2.0.0"]}
    def versions("elm/url", _opts), do: {:ok, ["1.0.0"]}
    def versions("elm/core", _opts), do: {:ok, ["1.0.5"]}
    def versions("elm/json", _opts), do: {:ok, ["1.1.3"]}
    def versions(_package, _opts), do: {:ok, ["1.0.0"]}

    @impl true
    def package_release("elm/http", "2.0.0", _opts) do
      {:ok,
       %{
         "dependencies" => %{
           "elm/core" => "1.0.0 <= v < 2.0.0",
           "elm/url" => "1.0.0 <= v < 2.0.0"
         }
       }}
    end

    def package_release("elm/url", "1.0.0", _opts) do
      {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}
    end

    def package_release("elm/core", "1.0.5", _opts), do: {:ok, %{"dependencies" => %{}}}

    def package_release("elm/json", "1.1.3", _opts),
      do: {:ok, %{"dependencies" => %{"elm/core" => "1.0.0 <= v < 2.0.0"}}}

    def package_release(_package, _version, _opts), do: {:ok, %{"dependencies" => %{}}}

    @impl true
    def readme(package, version, _opts), do: {:ok, "# #{package} #{version}"}
  end

  defmodule MockPebbleToolchain do
    @moduledoc false

    def package(_slug, _opts) do
      root = Path.join(System.tmp_dir!(), "ide_mcp_mock_publish")
      app_root = Path.join(root, "app")
      artifact_path = Path.join(root, "mock-app.pbw")
      File.mkdir_p!(Path.join(app_root, "build"))
      File.write!(artifact_path, "pbw")

      File.write!(
        Path.join(app_root, "build/appinfo.json"),
        Jason.encode!(%{
          "uuid" => "00000000-0000-0000-0000-000000000000",
          "shortName" => "Mock",
          "longName" => "Mock",
          "versionLabel" => "1.0.0",
          "companyName" => "Mock",
          "targetPlatforms" => ["basalt", "chalk"],
          "watchapp" => %{"watchface" => false}
        })
      )

      {:ok,
       %{
         status: :ok,
         artifact_path: artifact_path,
         app_root: app_root,
         build_result: %{status: :ok, output: "packaged"}
       }}
    end

    def publish(_slug, opts) do
      {:ok,
       %{
         status: :ok,
         command: "pebble publish --non-interactive",
         output: "published #{opts[:app_root]}",
         exit_code: 0,
         cwd: opts[:app_root]
       }}
    end

    def run_emulator(_slug, opts) do
      {:ok,
       %{
         status: :ok,
         command: "pebble install --emulator",
         output: "installed",
         exit_code: 0,
         cwd: Path.dirname(opts[:package_path] || "/tmp/mock-app.pbw")
       }}
    end
  end

  defmodule MockAppStorePublisher do
    @moduledoc false

    def publish(_project, opts) do
      {:ok,
       %{
         status: :ok,
         command: "native appstore publish",
         output: "published #{opts[:app_root]}",
         exit_code: 0,
         cwd: opts[:app_root]
       }}
    end
  end

  defmodule MockScreenshots do
    @moduledoc false

    def list(_slug, _opts) do
      root = Path.join(System.tmp_dir!(), "ide_mcp_mock_screenshots")
      chalk_path = Path.join([root, "chalk", "shot-new.png"])
      basalt_path = Path.join([root, "basalt", "shot-old.png"])
      File.mkdir_p!(Path.dirname(chalk_path))
      File.mkdir_p!(Path.dirname(basalt_path))
      File.write!(chalk_path, <<137, 80, 78, 71, 13, 10, 26, 10, "new">>)
      File.write!(basalt_path, <<137, 80, 78, 71, 13, 10, 26, 10, "old">>)

      {:ok,
       [
         %{
           filename: "shot-new.png",
           emulator_target: "chalk",
           url: "/screenshots/mock/chalk/shot-new.png",
           absolute_path: chalk_path,
           captured_at: "2026-01-01 00:00:01",
           mime_type: "image/png"
         },
         %{
           filename: "shot-old.png",
           emulator_target: "basalt",
           url: "/screenshots/mock/basalt/shot-old.png",
           absolute_path: basalt_path,
           captured_at: "2026-01-01 00:00:00",
           mime_type: "image/png"
         }
       ]}
    end

    def capture(_slug, opts) do
      target = opts[:emulator_target] || "basalt"

      {:ok,
       %{
         screenshot: %{
           filename: "shot-mock.png",
           emulator_target: target,
           url: "/screenshots/mock/#{target}/shot-mock.png",
           absolute_path: "/tmp/mock/#{target}/shot-mock.png",
           captured_at: "2026-01-01 00:00:00",
           mime_type: "image/png"
         },
         output: "captured",
         exit_code: 0,
         command: "pebble screenshot",
         cwd: "/tmp/mock"
       }}
    end
  end
end
