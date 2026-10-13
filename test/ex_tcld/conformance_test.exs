defmodule ExTcld.ConformanceTest do
  @moduledoc """
  Differential tests against a real `tclsh`.

  Every other test in this suite checks `ExTcld` against my understanding of
  Tcl. These check it against Tcl. That distinction matters: the parser
  originally rejected `a{b}c`, which is what Tcl's own `list` command emits,
  because I had assumed braces were significant anywhere in a word rather than
  only at the start of one. No amount of self-consistent testing would have
  found that.

  Skipped automatically when `tclsh` is not installed, so the suite still runs
  on a machine without it.
  """
  use ExUnit.Case, async: true

  alias ExTcld.List, as: TclList

  @tclsh System.find_executable("tclsh")

  setup_all do
    if @tclsh, do: :ok, else: {:ok, skip: true}
  end

  # Values chosen to hit every branch of Tcl's own quoting: whitespace, empty,
  # balanced and unbalanced braces, backslashes, quotes, sigils, multi-byte.
  @values [
    "plain",
    "a b",
    "",
    "a{b",
    "a}b",
    "a{b}c",
    "a{b}c{d}e",
    "\\",
    "a\\",
    "a\"b",
    "$HOME",
    "[pwd]",
    "a#b",
    "héllo wörld",
    "a\nb",
    "a\tb",
    "  leading",
    "trailing  ",
    "{",
    "}"
  ]

  describe "Tcl emits, ExTcld reads" do
    @tag :tclsh
    test "every value survives Tcl's list quoting" do
      if @tclsh do
        for value <- @values do
          emitted = tcl_quote(value)

          assert {:ok, [^value]} = TclList.from(emitted),
                 """
                 Tcl emitted #{inspect(emitted)} for #{inspect(value)},
                 which ExTcld did not read back as that value.
                 """
        end
      end
    end

    @tag :tclsh
    test "a multi-element Tcl list survives" do
      if @tclsh do
        emitted = tcl_list(@values)

        assert {:ok, decoded} = TclList.from(emitted)
        assert decoded == @values
      end
    end
  end

  describe "ExTcld emits, Tcl reads" do
    @tag :tclsh
    test "every value survives ExTcld's quoting when read by Tcl" do
      if @tclsh do
        for value <- @values do
          emitted = TclList.quote_element(value)

          assert tcl_llength(emitted) == 1,
                 "ExTcld emitted #{inspect(emitted)} for #{inspect(value)}; " <>
                   "tclsh reads it as #{tcl_llength(emitted)} elements, not 1"

          assert tcl_lindex(emitted, 0) == value,
                 "ExTcld emitted #{inspect(emitted)} for #{inspect(value)}; " <>
                   "tclsh reads element 0 as #{inspect(tcl_lindex(emitted, 0))}"
        end
      end
    end

    @tag :tclsh
    test "a multi-element ExTcld list is read with the same arity by Tcl" do
      if @tclsh do
        emitted = TclList.to_string(@values)
        assert tcl_llength(emitted) == length(@values)
      end
    end
  end

  describe "priv/tcl/tcld.tcl emits documents ExTcld reads" do
    @tag :tclsh
    test "a document written by tcld.tcl round-trips through ExTcld" do
      if @tclsh do
        source =
          run("""
          source #{tcld_package()}
          tcld::begin
          tcld::comment "generated for the conformance test"
          tcld::set name mytool
          tcld::set effect read-only
          tcld::set args [list --verbose --json]
          tcld::set meta [dict create lang tcl lines 240]
          tcld::set weird [list "a b" "c{d" "e\\\\" ""]
          puts -nonewline [tcld::render]
          """)

        assert {:ok, doc} = ExTcld.parse(source)
        assert {:ok, "mytool"} = ExTcld.Document.fetch(doc, "name")
        assert {:ok, "read-only"} = ExTcld.Document.fetch(doc, "effect")

        assert {:ok, raw_args} = ExTcld.Document.fetch(doc, "args")
        assert {:ok, ["--verbose", "--json"]} = TclList.from(raw_args)

        assert {:ok, raw_meta} = ExTcld.Document.fetch(doc, "meta")
        assert {:ok, %{"lang" => "tcl", "lines" => "240"}} = ExTcld.Dict.from(raw_meta)

        # The values most likely to break a hand-rolled quoter.
        assert {:ok, raw_weird} = ExTcld.Document.fetch(doc, "weird")
        assert {:ok, ["a b", "c{d", "e\\", ""]} = TclList.from(raw_weird)
      end
    end

    @tag :tclsh
    test "every conformance value survives a tcld.tcl document" do
      if @tclsh do
        assignments =
          @values
          |> Enum.with_index()
          |> Enum.map_join("\n", fn {value, index} ->
            # `binary decode base64` yields a byte string. Writing that to a
            # UTF-8 channel would double-encode it, so convert to a proper Tcl
            # string first. This is a harness concern, not a format one.
            ~s|tcld::set v#{index} [encoding convertfrom utf-8 [binary decode base64 "#{b64(value)}"]]|
          end)

        source =
          run("""
          source #{tcld_package()}
          tcld::begin
          #{assignments}
          puts -nonewline [tcld::render]
          """)

        assert {:ok, decoded} = ExTcld.decode(source)

        for {value, index} <- Enum.with_index(@values) do
          assert Map.fetch(decoded, "v#{index}") == {:ok, value},
                 "v#{index} expected #{inspect(value)}, got #{inspect(decoded["v#{index}"])}"
        end
      end
    end
  end

  defp tcld_package do
    Path.expand("../../priv/tcl/tcld.tcl", __DIR__)
  end

  # --- tclsh helpers ------------------------------------------------------
  #
  # Values cross the boundary base64-encoded so that the shell, the Tcl parser
  # and the test data cannot interfere with one another. Anything less careful
  # would make the harness itself the thing under test.

  defp tcl_quote(value) do
    run(~s|puts -nonewline [binary encode base64 [list [binary decode base64 "#{b64(value)}"]]]|)
    |> unb64()
  end

  defp tcl_list(values) do
    encoded = Enum.map_join(values, " ", &~s|[binary decode base64 "#{b64(&1)}"]|)
    run(~s|puts -nonewline [binary encode base64 [list #{encoded}]]|) |> unb64()
  end

  defp tcl_llength(source) do
    run(~s|puts -nonewline [llength [binary decode base64 "#{b64(source)}"]]|)
    |> String.to_integer()
  end

  defp tcl_lindex(source, index) do
    run(
      ~s|puts -nonewline [binary encode base64 [lindex [binary decode base64 "#{b64(source)}"] #{index}]]|
    )
    |> unb64()
  end

  defp run(script) do
    path =
      Path.join(
        System.tmp_dir!(),
        "ex_tcld_conformance_#{System.unique_integer([:positive])}.tcl"
      )

    try do
      File.write!(path, script <> "\n")
      {out, 0} = System.cmd(@tclsh, [path])
      String.trim(out)
    after
      File.rm(path)
    end
  end

  defp b64(value), do: Base.encode64(value)
  defp unb64(value), do: Base.decode64!(value)
end
