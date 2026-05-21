defmodule Ide.PackageDocs.Types do
  @moduledoc false

  @type validation_error ::
          :missing_exposed_modules
          | {:missing_module_comment, String.t(), String.t()}
          | {:missing_docs_list, String.t(), String.t()}
          | {:unknown_docs_reference, String.t(), String.t(), String.t()}
          | {:docs_reference_not_exposed, String.t(), String.t(), String.t()}
          | {:missing_declaration_comment, String.t(), String.t(), String.t()}
          | {:exposed_declaration_missing_from_docs, String.t(), String.t(), String.t()}

  @type io_error ::
          {:invalid_elm_json, String.t(), Jason.DecodeError.t() | File.posix() | :not_an_object}
          | {:remove_output_failed, String.t(), File.posix()}
          | {:write_failed, String.t(), File.posix()}
          | {:package_name_mismatch, String.t(), String.t() | nil}
          | File.posix()
          | Jason.EncodeError.t()

  @type export_error :: validation_error() | io_error()
end
