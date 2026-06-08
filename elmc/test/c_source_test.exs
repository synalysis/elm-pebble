defmodule Elmc.Backend.CCodegen.CSourceTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.CSource

  test "format indents brace blocks consistently" do
    input = """
    ElmcValue *foo(void) {
    (void)0;
      if (x) {
          y = 1;
      }
    return y;
    }
    """

    assert CSource.format(input) == """
    ElmcValue *foo(void) {
      (void)0;
      if (x) {
        y = 1;
      }
      return y;
    }
    """
  end

  test "format indents switch cases and bodies" do
    input = """
    switch (tag) {
    case ELMC_ONE:
        x = 1;
      break;
    default:
        x = 0;
      break;
    }
    """

    assert CSource.format(input) == """
    switch (tag) {
      case ELMC_ONE:
        x = 1;
        break;
      default:
        x = 0;
        break;
    }
    """
  end

  test "format leaves preprocessor directives at column zero" do
    input = """
    #if defined(__GNUC__)
    #pragma GCC diagnostic ignored "-Wunused-function"
    #endif
    """

    assert CSource.format(input) == """
    #if defined(__GNUC__)
    #pragma GCC diagnostic ignored "-Wunused-function"
    #endif
    """
  end

  test "format_block normalizes relative indentation" do
    assert CSource.format_block("  a\n    b\n", 4) == "    a\n      b"
  end

  test "indent prefixes non-blank lines" do
    assert CSource.indent("a\n\nb", 2) == "  a\n\n  b"
  end

  test "collapse_extra_newlines limits blank runs" do
    assert CSource.collapse_extra_newlines("a\n\n\n\nb") == "a\n\nb"
  end
end
