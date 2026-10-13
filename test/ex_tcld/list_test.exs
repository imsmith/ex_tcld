defmodule ExTcld.ListTest do
  @moduledoc """
  Tests for Tcl list interpretation. In Tcl every value is a string; list-ness
  is an interpretation a caller applies. These tests pin the splitting rules,
  including the cases where a naive whitespace split gets it wrong.
  """
  use ExUnit.Case, async: true

  alias ExTcld.List, as: TclList

  describe "from/1 — splitting" do
    test "splits on whitespace" do
      assert {:ok, ["a", "b", "c"]} = TclList.from("a b c")
    end

    test "collapses runs of whitespace" do
      assert {:ok, ["a", "b"]} = TclList.from("a   \t  b")
    end

    test "treats a braced group as one element and strips the outer braces" do
      assert {:ok, ["a b", "c"]} = TclList.from("{a b} c")
    end

    test "retains inner braces within a group" do
      assert {:ok, ["a {b c}", "d"]} = TclList.from("{a {b c}} d")
    end

    test "treats a quoted group as one element" do
      assert {:ok, ["a b", "c"]} = TclList.from(~S|"a b" c|)
    end

    test "honours a backslash-escaped space as part of a word" do
      assert {:ok, ["a b", "c"]} = TclList.from(~S|a\ b c|)
    end

    test "an empty string is the empty list" do
      assert {:ok, []} = TclList.from("")
    end

    test "a whitespace-only string is the empty list" do
      assert {:ok, []} = TclList.from("   \n\t ")
    end

    test "an empty braced element is an empty-string element, not absent" do
      assert {:ok, ["a", "", "b"]} = TclList.from("a {} b")
    end

    test "leading and trailing whitespace is ignored" do
      assert {:ok, ["a", "b"]} = TclList.from("  a b  ")
    end

    test "newlines separate elements like any other whitespace" do
      assert {:ok, ["a", "b"]} = TclList.from("a\nb")
    end
  end

  describe "from/1 — errors" do
    test "a leading brace that never closes is an error" do
      assert {:error, %ExTcld.Diagnostic{code: :unbalanced_brace}} = TclList.from("{a b")
    end

    test "unterminated quote is an error" do
      assert {:error, %ExTcld.Diagnostic{code: :unterminated_quote}} = TclList.from(~S|"a b|)
    end

    test "a braced group followed by text is an error" do
      # tclsh: `llength {a}b` => list element in braces followed by "b" instead of space
      assert {:error, %ExTcld.Diagnostic{code: :brace_followed_by_text}} = TclList.from("{a}b")
    end

    test "a quoted group followed by text is an error" do
      assert {:error, %ExTcld.Diagnostic{code: :quote_followed_by_text}} = TclList.from(~S|"a"b|)
    end
  end

  describe "from/1 — braces are only special at the start of a word" do
    # Verified against tclsh 8.6: `{` opens a group only as the first character
    # of a word. Anywhere else, both braces are ordinary characters, balanced
    # or not. ex_tcld previously rejected these, which meant it could not read
    # Tcl's own `list` output.
    test "a close brace inside a bare word is ordinary" do
      assert {:ok, ["a", "b}"]} = TclList.from("a b}")
    end

    test "an open brace inside a bare word is ordinary" do
      assert {:ok, ["a", "b{"]} = TclList.from("a b{")
    end

    test "balanced braces inside a bare word are ordinary" do
      assert {:ok, ["a{b}c"]} = TclList.from("a{b}c")
    end

    test "repeated braces inside a bare word are ordinary" do
      assert {:ok, ["a{b}c{d}e"]} = TclList.from("a{b}c{d}e")
    end

    test "an unbalanced brace inside a bare word is ordinary" do
      assert {:ok, ["x{y"]} = TclList.from("x{y")
    end
  end

  describe "nesting" do
    test "a nested list round-trips through two interpretations" do
      assert {:ok, [outer]} = TclList.from("{a b c}")
      assert {:ok, ["a", "b", "c"]} = TclList.from(outer)
    end

    test "pairs of pairs, as roots.tcl is shaped" do
      source = "{/home/imsmith/github github} {{/home/imsmith/Calibre Library} calibre}"
      assert {:ok, [first, second]} = TclList.from(source)
      assert {:ok, ["/home/imsmith/github", "github"]} = TclList.from(first)
      assert {:ok, ["/home/imsmith/Calibre Library", "calibre"]} = TclList.from(second)
    end
  end

  describe "to_string/1" do
    test "quotes elements containing whitespace" do
      assert TclList.to_string(["a b", "c"]) == "{a b} c"
    end

    test "leaves simple elements bare" do
      assert TclList.to_string(["a", "b"]) == "a b"
    end

    test "renders an empty element as empty braces" do
      assert TclList.to_string(["a", "", "b"]) == "a {} b"
    end

    test "round-trips through from/1" do
      elements = ["a b", "c", "", "d {e} f"]
      assert {:ok, ^elements} = elements |> TclList.to_string() |> TclList.from()
    end
  end
end
