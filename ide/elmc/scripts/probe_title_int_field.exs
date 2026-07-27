alias ElmEx.Frontend.Bridge
alias ElmEx.IR.Lowerer
alias Elmc.Backend.CCodegen.IRQueries
alias Elmc.Backend.Plan.Lower.Record

app = Path.expand("../../elm_pebble_dev", __DIR__)
{:ok, p} = Bridge.load_project(app)
{:ok, ir} = Lowerer.lower_project(p)
Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(ir))

IO.puts("int_field?(title)=#{Record.int_field?("title")}")

types = Process.get(:elmc_record_field_types)

for {key, fields} <- types, {"title", t} <- fields, t == "Int" do
  IO.puts("Int title in #{inspect(key)}")
end
