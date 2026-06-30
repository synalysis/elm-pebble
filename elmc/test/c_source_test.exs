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

  test "format indents switch cases when label and opening brace share a line" do
    input = """
    static ElmcValue *restore(ElmcValue *direction) {
      switch (direction) {
          case ELMC_UNION_LEFT: {
          tmp = cells;
          break;
        }
      }
    }
    
      """

    assert CSource.format(input) == """
    static ElmcValue *restore(ElmcValue *direction) {
      switch (direction) {
        case ELMC_UNION_LEFT: {
          tmp = cells;
          break;
        }
      }
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

  test "format splits compact if-assignment lines onto the next line" do
    input = """
    if (native_mod_2 != 0) {
      native_mod_2 = seed % native_mod_base_2;
      if (native_mod_2 < 0) native_mod_2 += (native_mod_base_2 < 0 ? -native_mod_base_2 : native_mod_base_2);
    }
    
      """

    assert CSource.format(input) == """
    if (native_mod_2 != 0) {
      native_mod_2 = seed % native_mod_base_2;
      if (native_mod_2 < 0)
        native_mod_2 += (native_mod_base_2 < 0 ? -native_mod_base_2 : native_mod_base_2);
    }
    """
  end

  test "format keeps compact if-break and if-return on one line" do
    input = """
    if (direct_item_i == last_ref) break;
    if (!writer) return -1;
    
      """

    assert CSource.format(input) == """
    if (direct_item_i == last_ref) break;
    if (!writer) return -1;
    """
  end

  test "format removes adjacent retain release temp pairs" do
    input = """
    ElmcValue *foo(ElmcValue *model) {
      ElmcValue *tmp_1 = elmc_retain(model);
      elmc_release(tmp_1);
      return elmc_retain(model);
    }
    
      """

    assert CSource.format(input) == """
    ElmcValue *foo(ElmcValue *model) {
      return elmc_retain(model);
    }
    """
  end

  test "format compacts unit increment and decrement assignments" do
    input = """
    void step(void) {
      list_search_target_67 -= 1;
      list_search_index_67 += 1;
      direct_item_i += direct_step;
    }
    
      """

    assert CSource.format(input) == """
    void step(void) {
      list_search_target_67--;
      list_search_index_67++;
      direct_item_i += direct_step;
    }
    """
  end

  test "format borrows record field temps for borrow_arg wrapper calls" do
    input = """
    static ElmcValue *elmc_fn_Main_callee(ElmcValue ** const args, const int argc) {
      /* Ownership policy: borrow_arg, retain_result */
      (void)args;
      (void)argc;
      return elmc_int_zero();
    }

    ElmcValue *caller(ElmcValue *model, ElmcValue *cells) {
      ElmcValue *tmp_13 = elmc_record_get_index(model, 6 /* seed */);

      ElmcValue *call_args_14[2] = { tmp_13, cells };
      ElmcValue *tmp_14 = elmc_fn_Main_callee(call_args_14, 2);

      elmc_release(tmp_13);
      return tmp_14;
    }
    
      """

    formatted = CSource.format(input)

    assert formatted =~
             "ElmcValue *call_args_14[2] = { ELMC_RECORD_GET_INDEX(model, 6 /* seed */), cells };"

    refute formatted =~ "elmc_record_get_index(model, 6 /* seed */)"
    refute formatted =~ "elmc_release(tmp_13)"
  end

  test "format borrows record field temps for borrow_arg direct calls" do
    input = """
    static ElmcValue *elmc_fn_Main_callee(ElmcValue *seed, ElmcValue *cells) {
      /* Ownership policy: borrow_arg, retain_result, direct_call_abi */
      return elmc_tuple2(seed, cells);
    }

    ElmcValue *caller(ElmcValue *model, ElmcValue *cells) {
      ElmcValue *tmp_13 = elmc_record_get_index(model, 6 /* seed */);

      ElmcValue *tmp_14 = elmc_fn_Main_callee(tmp_13, cells);

      elmc_release(tmp_13);
      return tmp_14;
    }
    
      """

    formatted = CSource.format(input)

    assert formatted =~
             "ElmcValue *tmp_14 = elmc_fn_Main_callee(ELMC_RECORD_GET_INDEX(model, 6 /* seed */), cells);"

    refute formatted =~ "elmc_record_get_index(model, 6 /* seed */)"
    refute formatted =~ "elmc_release(tmp_13)"
  end

  test "format indents CATCH_BEGIN body and brace-wrapped CATCH_BREAK" do
    input = """
    static int foo(void) {
    int direct_rc = 0;
    x = 1;
    if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
    CATCH_BREAK;
    }

    return direct_rc;
    CATCH_END;
    }
    
      
      """

    assert CSource.format(input) == """
    static int foo(void) {
      int direct_rc = 0;
      x = 1;
      if (elmc_scene_writer_push_cmd(writer, &scene_cmd) != 0) {
        CATCH_BREAK;
      }

      return direct_rc;
    CATCH_END;
    }
    """
  end
end
