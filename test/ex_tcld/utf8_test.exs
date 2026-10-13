defmodule ExTcld.Utf8Test do
  @moduledoc """
  UTF-8 and escape-sequence coverage.

  The scanner walks binaries with `utf8` pattern matching, so multi-byte
  characters must survive braced, quoted and bare contexts, must not be split
  by the whitespace test, and must survive the encoder's per-character escaping
  path — which rebuilds strings a codepoint at a time and is therefore the most
  likely place for a multi-byte character to be corrupted.
  """
  use ExUnit.Case, async: true

  alias ExTcld.List, as: TclList

  describe "multi-byte characters survive each quoting form" do
    test "braced" do
      assert {:ok, %{"K" => "héllo wörld"}} = ExTcld.decode("set K {héllo wörld}")
    end

    test "quoted" do
      assert {:ok, %{"K" => "héllo wörld"}} = ExTcld.decode(~s|set K "héllo wörld"|)
    end

    test "bare" do
      assert {:ok, %{"K" => "héllo"}} = ExTcld.decode("set K héllo")
    end

    test "CJK in a list" do
      assert {:ok, ["日本語", "テスト"]} = TclList.from("日本語 テスト")
    end

    test "emoji, including a multi-codepoint grapheme" do
      assert {:ok, ["👍", "👨‍👩‍👧‍👦"]} = TclList.from("👍 👨‍👩‍👧‍👦")
    end

    test "a multi-byte character adjacent to a brace is not split" do
      assert {:ok, ["é"]} = TclList.from("{é}")
    end

    test "combining marks are preserved byte-for-byte" do
      combining = "é"
      assert {:ok, [^combining]} = TclList.from("{" <> combining <> "}")
    end
  end

  describe "the escaping path preserves multi-byte characters" do
    test "quote_element leaves a bare multi-byte word alone" do
      assert TclList.quote_element("héllo") == "héllo"
    end

    test "quote_element braces a multi-byte value containing a space" do
      assert TclList.quote_element("héllo wörld") == "{héllo wörld}"
    end

    test "the backslash-escape fallback preserves multi-byte characters" do
      # Unbalanced brace forces escape_specials/1, which rebuilds the string
      # one codepoint at a time.
      escaped = TclList.quote_element("héllo{wörld")
      assert {:ok, ["héllo{wörld"]} = TclList.from(escaped)
    end

    test "a value that needs escaping is actually escaped, not passed through" do
      # Guards the hole mutation testing exposed: asserting only that the value
      # round-trips passes even when no escaping happens, because a bare word
      # containing { also round-trips. Assert the spelling.
      assert TclList.quote_element("a{b") == "a\\{b"
    end

    test "escaping is used only when braces would not balance" do
      assert TclList.quote_element("a{b}c") == "{a{b}c}"
    end
  end

  describe "escape sequences" do
    test "recognised control escapes in a quoted word" do
      assert {:ok, ["\a\b\f\n\r\t\v"]} = TclList.from(~S|"\a\b\f\n\r\t\v"|)
    end

    test "an unrecognised escape stands for the character itself" do
      assert {:ok, ["$"]} = TclList.from(~S|\$|)
      assert {:ok, ["["]} = TclList.from(~S|\[|)
    end

    test "an escaped backslash yields one backslash" do
      assert {:ok, ["\\"]} = TclList.from(~S|\\|)
    end

    test "an escaped space keeps a word together" do
      assert {:ok, ["a b"]} = TclList.from(~S|a\ b|)
    end

    test "backslashes are literal inside braces, as Tcl specifies" do
      assert {:ok, ["a\\nb"]} = TclList.from(~S|{a\nb}|)
    end

    test "a trailing lone backslash is preserved" do
      assert {:ok, ["a\\"]} = TclList.from("a\\")
    end

    test "a value ending in a backslash survives a round trip" do
      escaped = TclList.quote_element("a\\")
      assert {:ok, ["a\\"]} = TclList.from(escaped)
    end

    test "a lone backslash survives a round trip" do
      escaped = TclList.quote_element("\\")
      assert {:ok, ["\\"]} = TclList.from(escaped)
    end
  end

  describe "substitution detection is codepoint-safe" do
    test "a multi-byte value with no sigil raises no warning" do
      assert {:ok, %ExTcld.Document{diagnostics: []}} = ExTcld.parse("set K héllo")
    end

    test "a sigil after a multi-byte character is still detected" do
      assert {:ok, %ExTcld.Document{diagnostics: [d]}} = ExTcld.parse("set K hé$llo")
      assert d.code == :substitution_not_performed
    end

    test "an escaped sigil after a multi-byte character raises no warning" do
      assert {:ok, %ExTcld.Document{diagnostics: []}} = ExTcld.parse(~S|set K hé\$llo|)
    end
  end
end
