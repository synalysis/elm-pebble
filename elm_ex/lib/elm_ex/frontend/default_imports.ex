defmodule ElmEx.Frontend.DefaultImports do
  @moduledoc false

  @default_module_names ["Basics", "List", "Maybe", "Result", "String", "Char", "Tuple", "Debug"]

  @default_import_entries [
    %{"module" => "Basics", "as" => nil, "exposing" => ".."},
    %{"module" => "List", "as" => nil, "exposing" => ["List", "::"]},
    %{"module" => "Maybe", "as" => nil, "exposing" => ["Maybe", "Just", "Nothing"]},
    %{"module" => "Result", "as" => nil, "exposing" => ["Result", "Ok", "Err"]},
    %{"module" => "String", "as" => nil, "exposing" => ["String"]},
    %{"module" => "Char", "as" => nil, "exposing" => ["Char"]},
    %{"module" => "Tuple", "as" => nil, "exposing" => nil},
    %{"module" => "Debug", "as" => nil, "exposing" => nil}
  ]

  @spec module_names() :: [String.t()]
  def module_names, do: @default_module_names

  @spec import_entries() :: [map()]
  def import_entries, do: @default_import_entries
end
