Mix.Task.run("app.start")
workspace = Path.join(System.tmp_dir!(), "g2048_#{System.unique_integer([:positive])}")
:ok = Ide.ProjectTemplates.apply_template("game-2048", workspace)
{:ok, pkg} =
  Ide.PebbleToolchain.package("g2048",
    workspace_root: workspace,
    target_type: "app",
    project_name: "2048",
    target_platforms: ["diorite"],
    source_roots: ["watch", "protocol", "phone"],
    emulator_storage_logs: true
  )

IO.puts(pkg.artifact_path)
IO.puts(File.stat!(pkg.artifact_path).size)
