defmodule ExTcld.TypeCheckTest do
  @moduledoc """
  Pins the contract between `ExTcld` and Elixir 1.20's type checker.

  The checker infers argument and return types from the guards, struct patterns
  and bodies of every public function, then verifies call sites against them at
  compile time. Nothing here reads `@spec`; specs serve ExDoc and Dialyzer.

  Each test compiles a small caller of the API and asserts either that a wrong
  argument is reported as a type warning, or that a correct caller compiles
  with no warnings at all. If a guard is loosened or removed, the matching test
  fails.
  """
  use ExUnit.Case, async: true

  @misuses [
    {~S|ExTcld.parse(123)|, "ExTcld.parse/1"},
    {~S|ExTcld.parse!(123)|, "ExTcld.parse!/1"},
    {~S|ExTcld.decode(:nope)|, "ExTcld.decode/1"},
    {~S|ExTcld.List.from(:nope)|, "ExTcld.List.from/1"},
    {~S|ExTcld.List.from!(:nope)|, "ExTcld.List.from!/1"},
    {~S|ExTcld.Dict.from(%{})|, "ExTcld.Dict.from/1"},
    {~S|ExTcld.Value.new("x", :weird)|, "ExTcld.Value.new/2"},
    {~S|ExTcld.Diagnostic.error(:bogus, "m")|, "ExTcld.Diagnostic.error/2"},
    {~S|ExTcld.Diagnostic.warning(:bogus, "m")|, "ExTcld.Diagnostic.warning/2"},
    {~S|ExTcld.Document.fetch(ExTcld.Document.new([]), 42)|, "ExTcld.Document.fetch/2"},
    {~S|ExTcld.Limits.new(%{max_depth: 1})|, "ExTcld.Limits.new/1"},
    {~S|ExTcld.Limits.check_depth(1, %{max_depth: 1})|, "ExTcld.Limits.check_depth/2"},
    {~S|ExTcld.Parser.Lexer.scan_word("a", %{})|, "ExTcld.Parser.Lexer.scan_word/2"},
    {~S|ExTcld.Parser.Grammar.parse(1, ExTcld.Limits.new())|, "ExTcld.Parser.Grammar.parse/2"}
  ]

  describe "argument types are checked at the call site" do
    for {call, mfa} <- @misuses do
      test "#{call} is a type warning" do
        assert [message] = compile_warnings(unquote(call))
        assert message =~ "incompatible types given to #{unquote(mfa)}"
      end
    end
  end

  describe "return types are inferred" do
    test "an unreachable clause over Document.fetch/2 is reported" do
      assert [message] =
               compile_warnings("""
               case ExTcld.Document.fetch(ExTcld.Document.new([]), "A") do
                 {:ok, string} -> string
                 :error -> nil
                 :missing -> nil
               end
               """)

      assert message =~ "clause will never match"
    end
  end

  describe "correct callers" do
    test "the README pipeline compiles without warnings" do
      assert compile_warnings("""
             {:ok, doc} = ExTcld.parse("set roots {{/a alpha} {/b beta}}")
             {:ok, raw} = ExTcld.Document.fetch(doc, "roots")
             {:ok, pairs} = ExTcld.List.from(raw)
             Enum.map(pairs, &ExTcld.List.from!/1)
             """) == []
    end

    test "every diagnostic code is accepted" do
      calls =
        Enum.map_join(
          ~w(unbalanced_brace unterminated_quote brace_followed_by_text quote_followed_by_text
             incomplete_set unsupported_command odd_dict_length substitution_not_performed
             limit_exceeded)a,
          "\n",
          &"ExTcld.Diagnostic.error(#{inspect(&1)}, \"m\")"
        )

      assert compile_warnings(calls) == []
    end
  end

  # Compiles `body` as the sole function of a fresh module and returns the
  # compiler's warning messages. The module is removed afterwards so repeated
  # runs do not accumulate code.
  defp compile_warnings(body) do
    module = Module.concat(__MODULE__, "Probe#{System.unique_integer([:positive])}")
    source = "defmodule #{inspect(module)} do\n  def run do\n#{body}\n  end\nend\n"

    {_, diagnostics} = Code.with_diagnostics(fn -> Code.compile_string(source) end)

    :code.purge(module)
    :code.delete(module)

    for %{severity: :warning, message: message} <- diagnostics, do: message
  end
end
