defmodule ExTcldTest do
  @moduledoc """
  Contract tests for the `ExTcld` public API: parse, decode, encode and
  round-trip fidelity, plus the parser's explicit refusal to perform Tcl
  variable or command substitution.
  """
  use ExUnit.Case, async: true

  doctest ExTcld

  alias ExTcld.{Assignment, Comment, Document, Value}

  describe "parse/2 — documents" do
    test "parses a single set assignment" do
      assert {:ok, %Document{body: [%Assignment{name: "X", value: %Value{string: "5"}}]}} =
               ExTcld.parse("set X 5")
    end

    test "parses multiple assignments in order" do
      assert {:ok, %Document{body: [a, b]}} = ExTcld.parse("set A 1\nset B 2")
      assert %Assignment{name: "A"} = a
      assert %Assignment{name: "B"} = b
    end

    test "parses a braced value preserving inner content verbatim" do
      assert {:ok, %Document{body: [%Assignment{value: v}]}} = ExTcld.parse("set L {a b c}")
      assert v.string == "a b c"
      assert v.quoting == :brace
    end

    test "parses a quoted value applying backslash escapes" do
      assert {:ok, %Document{body: [%Assignment{value: v}]}} = ExTcld.parse(~S|set S "a\tb"|)
      assert v.string == "a\tb"
      assert v.quoting == :quote
    end

    test "parses a bare word" do
      assert {:ok, %Document{body: [%Assignment{value: v}]}} = ExTcld.parse("set W hello")
      assert v.string == "hello"
      assert v.quoting == :bare
    end

    test "nested braces are balanced and retained in the string" do
      assert {:ok, %Document{body: [%Assignment{value: v}]}} = ExTcld.parse("set N {a {b c} d}")
      assert v.string == "a {b c} d"
    end

    test "an empty braced value is the empty string" do
      assert {:ok, %Document{body: [%Assignment{value: v}]}} = ExTcld.parse("set E {}")
      assert v.string == ""
    end

    test "unbalanced braces are an error, not a silent truncation" do
      assert {:error, [%ExTcld.Diagnostic{code: :unbalanced_brace}]} = ExTcld.parse("set B {a b")
    end

    test "an unterminated quote is an error" do
      assert {:error, [%ExTcld.Diagnostic{code: :unterminated_quote}]} =
               ExTcld.parse(~S|set Q "ab|)
    end

    test "a set with no value is an error" do
      assert {:error, [%ExTcld.Diagnostic{code: :incomplete_set}]} = ExTcld.parse("set X")
    end

    test "a command other than set is refused explicitly" do
      assert {:error, [%ExTcld.Diagnostic{code: :unsupported_command} = d]} =
               ExTcld.parse("foreach x {1 2} {}")

      assert d.message =~ "foreach"
    end
  end

  describe "parse/2 — comments" do
    test "captures a standalone comment" do
      assert {:ok, %Document{body: [%Comment{text: " a note"}]}} = ExTcld.parse("# a note")
    end

    test "keeps comments and assignments in source order" do
      assert {:ok, %Document{body: [%Comment{}, %Assignment{}, %Comment{}]}} =
               ExTcld.parse("# one\nset X 1\n# two")
    end

    test "a hash inside a braced value is data, not a comment" do
      assert {:ok, %Document{body: [%Assignment{value: v}]}} = ExTcld.parse("set H {a # b}")
      assert v.string == "a # b"
    end

    test "a hash after a value on the same line is data, not a comment" do
      # Tcl only treats # as a comment at the start of a command.
      assert {:ok, %Document{body: [%Assignment{value: v}]}} = ExTcld.parse("set H a#b")
      assert v.string == "a#b"
    end
  end

  describe "parse/2 — substitution refusal" do
    test "warns on a dollar sign in a bare word" do
      assert {:ok,
              %Document{diagnostics: [%ExTcld.Diagnostic{code: :substitution_not_performed}]}} =
               ExTcld.parse("set V $HOME")
    end

    test "warns on a bracket in a quoted word" do
      assert {:ok,
              %Document{diagnostics: [%ExTcld.Diagnostic{code: :substitution_not_performed}]}} =
               ExTcld.parse(~S|set V "[pwd]"|)
    end

    test "does not warn inside braces, which never substitute in Tcl either" do
      assert {:ok, %Document{diagnostics: []}} = ExTcld.parse("set V {$HOME [pwd]}")
    end

    test "the warning is a diagnostic, not a failure" do
      assert {:ok, %Document{body: [%Assignment{value: v}]}} = ExTcld.parse("set V $HOME")
      assert v.string == "$HOME"
    end
  end

  describe "decode/2" do
    test "decodes assignments into a map of name => string" do
      assert {:ok, %{"A" => "1", "B" => "2"}} = ExTcld.decode("set A 1\nset B 2")
    end

    test "decodes a braced value as its literal string" do
      assert {:ok, %{"L" => "a b c"}} = ExTcld.decode("set L {a b c}")
    end

    test "ignores comments" do
      assert {:ok, %{"A" => "1"}} = ExTcld.decode("# note\nset A 1")
    end

    test "propagates parse errors" do
      assert {:error, [%ExTcld.Diagnostic{}]} = ExTcld.decode("set B {a b")
    end
  end

  describe "parse!/1" do
    test "returns the document on success" do
      assert %Document{} = ExTcld.parse!("set A 1")
    end

    test "raises on failure" do
      assert_raise ExTcld.ParseError, fn -> ExTcld.parse!("set B {a b") end
    end
  end

  describe "encode/1 — round-trip" do
    test "round-trips a simple assignment" do
      assert_round_trip("set A 1")
    end

    test "round-trips braced values" do
      assert_round_trip("set L {a b c}")
    end

    test "round-trips nested braces" do
      assert_round_trip("set N {a {b c} d}")
    end

    test "round-trips comments in place" do
      assert_round_trip("# one\nset X 1\n# two")
    end

    test "encodes a value containing spaces with braces" do
      {:ok, iodata} = ExTcld.encode(%{"K" => "a b"})
      assert IO.iodata_to_binary(iodata) == "set K {a b}\n"
    end

    test "encodes an empty string as empty braces" do
      {:ok, iodata} = ExTcld.encode(%{"K" => ""})
      assert IO.iodata_to_binary(iodata) == "set K {}\n"
    end

    test "encodes a value with unbalanced braces using backslash escapes" do
      {:ok, iodata} = ExTcld.encode(%{"K" => "a{b"})
      encoded = IO.iodata_to_binary(iodata)
      assert {:ok, %{"K" => "a{b"}} = ExTcld.decode(encoded)
    end
  end

  defp assert_round_trip(source) do
    assert {:ok, doc} = ExTcld.parse(source)
    assert {:ok, iodata} = ExTcld.encode(doc)
    assert String.trim_trailing(IO.iodata_to_binary(iodata)) == String.trim_trailing(source)
  end
end
