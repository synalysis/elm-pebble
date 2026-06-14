defmodule Ide.MixProject do
  use Mix.Project

  def project do
    [
      app: :ide,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      dialyzer: [
        plt_add_apps: [:mix, :elm_ex, :elmc, :elmx],
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      aliases: aliases(),
      deps: deps()
    ]
  end

  def cli do
    [
      preferred_envs: [
        test: :test,
        "test.unit": :test,
        "test.integration": :test,
        "test.slow": :test,
        "test.mcp": :test,
        "test.corpus": :test,
        "test.corpus_step": :test,
        "test.pbw_gate": :test
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Ide.Application, []},
      extra_applications: [:logger, :runtime_tools, :ssl, :crypto]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.20"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, "~> 0.21"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.0"},
      {:floki, ">= 0.30.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.5"},
      # SMTP adapter (runtime when SMTP_RELAY is set) needs gen_smtp for :gen_smtp_client and :mimemail
      {:gen_smtp, "~> 1.0"},
      {:finch, "~> 0.13"},
      {:req, "~> 0.5"},
      {:muontrap, "~> 1.7"},
      {:websockex, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:earmark, "~> 1.4"},
      {:html_sanitize_ex, "~> 1.4"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:elmc, path: "../elmc"},
      {:elm_ex, path: "../elm_ex"},
      {:elmx, path: "../elmx"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "ide.boundary_check", "test"],
      "test.unit": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "ide.boundary_check",
        "test --exclude integration --exclude slow --exclude live_emulator --exclude template_corpus --exclude template_corpus_step --exclude compiled_elixir_corpus --exclude template_compile_gate --exclude template_pbw_gate --max-cases 4"
      ],
      "test.integration": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "ide.boundary_check",
        "test --only integration --include slow --max-cases 1"
      ],
      "test.slow": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "ide.boundary_check",
        "test --only slow --include slow --max-cases 1"
      ],
      "test.mcp": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "ide.boundary_check",
        "test test/ide/mcp --include integration --include slow --max-cases 1"
      ],
      "test.corpus": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "ide.boundary_check",
        "test --only template_corpus --include template_corpus --max-cases 1"
      ],
      "test.corpus_step": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "ide.boundary_check",
        "test --only template_corpus_step --include template_corpus_step --max-cases 1"
      ],
      "test.pbw_gate": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "ide.boundary_check",
        "test test/ide/template_pbw_gate_test.exs --only template_pbw_gate --include template_pbw_gate --max-cases 1"
      ],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind ide", "esbuild ide"],
      "assets.typecheck": ["cmd npm run typecheck --prefix assets"],
      "assets.deploy": [
        "tailwind ide --minify",
        "esbuild ide --minify",
        "phx.digest"
      ]
    ]
  end
end
