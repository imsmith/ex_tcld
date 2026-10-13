defmodule ExTcld.Parser.Lexer do
  @moduledoc """
  Scans a single Tcl word from the head of a binary.

  Three word forms exist, and they differ in how backslashes are treated:

  * **Braced** — `{...}`. Content is taken verbatim, backslashes included.
    Braces must balance; `\\{` and `\\}` are excluded from the balance count.
    This is the only form in which `$` and `[` are unambiguously literal.
  * **Quoted** — `"..."`. Backslash escapes are applied. Terminates at the
    first unescaped `"`.
  * **Bare** — an unquoted word. Backslash escapes are applied. Terminates at
    the first unescaped whitespace character.

  The scanner never performs variable or command substitution. Callers detect
  `$` and `[` via `substitution_risk?/2` and raise a warning instead.

  Whitespace handling belongs to the caller, because command context stops at a
  newline and list context does not.
  """

  alias ExTcld.{Diagnostic, Limits, Value}

  @whitespace [?\s, ?\t, ?\n, ?\r, ?\f, ?\v]

  @doc """
  Returns true when `char` is Tcl whitespace.

  ## Examples

      iex> ExTcld.Parser.Lexer.whitespace?(?\\s)
      true

      iex> ExTcld.Parser.Lexer.whitespace?(?a)
      false
  """
  @spec whitespace?(char()) :: boolean()
  def whitespace?(char), do: char in @whitespace

  @doc """
  Scans one word from the head of `source`, which must not begin with
  whitespace.

  Returns the scanned `ExTcld.Value` and the unconsumed remainder.

  ## Examples

      iex> {:ok, v, rest} = ExTcld.Parser.Lexer.scan_word("{a b} c", ExTcld.Limits.new())
      iex> {v.string, v.quoting, rest}
      {"a b", :brace, " c"}

      iex> {:ok, v, ""} = ExTcld.Parser.Lexer.scan_word("hello", ExTcld.Limits.new())
      iex> v.string
      "hello"
  """
  @spec scan_word(binary(), Limits.t()) ::
          {:ok, Value.t(), binary()} | {:error, Diagnostic.t()}
  def scan_word("{" <> rest, %Limits{} = limits), do: scan_braced(rest, limits)
  def scan_word("\"" <> rest, %Limits{} = limits), do: scan_quoted(rest, limits)
  def scan_word(source, %Limits{} = limits) when is_binary(source), do: scan_bare(source, limits)

  # --- braced -------------------------------------------------------------
  # Content is verbatim. Depth counting ignores backslash-escaped braces.

  defp scan_braced(source, limits) do
    with {:ok, content, rest} <- take_braced(source, 1, [], limits),
         :ok <- word_must_end(rest, :brace_followed_by_text, "braces") do
      {:ok, Value.new(content, :brace, "{" <> content <> "}"), rest}
    end
  end

  # Tcl requires a braced or quoted group to be followed by whitespace or the
  # end of input. `{a}b` is an error, not the word `ab` — verified against
  # tclsh, which reports "list element in braces followed by \"b\" instead of
  # space".
  defp word_must_end(<<>>, _code, _what), do: :ok

  defp word_must_end(<<char::utf8, _rest::binary>> = source, code, what) do
    if whitespace?(char) do
      :ok
    else
      {:error,
       Diagnostic.error(
         code,
         "list element in #{what} followed by #{inspect(String.first(source))} instead of space"
       )}
    end
  end

  defp take_braced(<<>>, _depth, _acc, _limits) do
    {:error, Diagnostic.error(:unbalanced_brace, "unbalanced { — reached end of input")}
  end

  defp take_braced(<<?\\, char::utf8, rest::binary>>, depth, acc, limits) do
    take_braced(rest, depth, [<<char::utf8>>, "\\" | acc], limits)
  end

  defp take_braced(<<?{, rest::binary>>, depth, acc, limits) do
    case Limits.check_depth(depth + 1, limits) do
      :ok -> take_braced(rest, depth + 1, ["{" | acc], limits)
      {:error, %Diagnostic{}} = error -> error
    end
  end

  defp take_braced(<<?}, rest::binary>>, 1, acc, _limits) do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp take_braced(<<?}, rest::binary>>, depth, acc, limits) do
    take_braced(rest, depth - 1, ["}" | acc], limits)
  end

  defp take_braced(<<char::utf8, rest::binary>>, depth, acc, limits) do
    take_braced(rest, depth, [<<char::utf8>> | acc], limits)
  end

  # --- quoted -------------------------------------------------------------

  defp scan_quoted(source, limits) do
    with {:ok, content, rest} <- take_quoted(source, [], limits),
         :ok <- word_must_end(rest, :quote_followed_by_text, "quotes") do
      {:ok, Value.new(content, :quote, consumed(source, rest)), rest}
    end
  end

  defp take_quoted(<<>>, _acc, _limits) do
    {:error, Diagnostic.error(:unterminated_quote, ~s(unterminated " — reached end of input))}
  end

  defp take_quoted(<<?\\, char::utf8, rest::binary>>, acc, limits) do
    take_quoted(rest, [unescape(char) | acc], limits)
  end

  defp take_quoted(<<?", rest::binary>>, acc, _limits) do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp take_quoted(<<char::utf8, rest::binary>>, acc, limits) do
    take_quoted(rest, [<<char::utf8>> | acc], limits)
  end

  # --- bare ---------------------------------------------------------------

  defp scan_bare(source, limits) do
    case take_bare(source, [], limits) do
      {:ok, content, rest} -> {:ok, Value.new(content, :bare, consumed(source, rest)), rest}
      {:error, %Diagnostic{}} = error -> error
    end
  end

  # The slice of `source` that was consumed to produce `rest`. Retained so that
  # substitution detection can inspect the original spelling, where the
  # difference between `$HOME` and `\$HOME` still exists.
  defp consumed(source, rest) do
    binary_part(source, 0, byte_size(source) - byte_size(rest))
  end

  defp take_bare(<<>>, acc, _limits) do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), <<>>}
  end

  defp take_bare(<<?\\, char::utf8, rest::binary>>, acc, limits) do
    take_bare(rest, [unescape(char) | acc], limits)
  end

  # No brace clause here on purpose. In Tcl, `{` opens a group only as the
  # first character of a word; anywhere else both braces are ordinary
  # characters, balanced or not. `a b}` is two elements and `a{b}c{d}e` is one.
  # Rejecting them made ex_tcld unable to read Tcl's own `list` output.
  defp take_bare(<<char::utf8, rest::binary>> = source, acc, limits) do
    if whitespace?(char) do
      {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), source}
    else
      take_bare(rest, [<<char::utf8>> | acc], limits)
    end
  end

  # Tcl's backslash escapes. Any character not listed stands for itself, which
  # is what makes `\ ` a literal space and `\$` a literal dollar sign.
  defp unescape(?a), do: <<7>>
  defp unescape(?b), do: "\b"
  defp unescape(?f), do: "\f"
  defp unescape(?n), do: "\n"
  defp unescape(?r), do: "\r"
  defp unescape(?t), do: "\t"
  defp unescape(?v), do: <<11>>
  defp unescape(char), do: <<char::utf8>>

  @doc """
  Returns true when a value would have undergone substitution in a real Tcl
  interpreter but did not here.

  Inspects the value's `:raw` field — the original spelling — because an escaped
  `\\$` is a literal dollar sign and must not warn, while a bare `$` must.
  Braced values never substitute in Tcl either, so they always return `false`.

  ## Examples

      iex> ExTcld.Parser.Lexer.substitution_risk?(ExTcld.Value.new("$HOME", :bare, "$HOME"))
      true

      iex> ExTcld.Parser.Lexer.substitution_risk?(ExTcld.Value.new("$HOME", :bare, "\\\\$HOME"))
      false

      iex> ExTcld.Parser.Lexer.substitution_risk?(ExTcld.Value.new("$HOME", :brace, "{$HOME}"))
      false
  """
  @spec substitution_risk?(Value.t()) :: boolean()
  def substitution_risk?(%Value{quoting: :brace}), do: false
  def substitution_risk?(%Value{raw: nil, string: string}), do: unescaped_sigil?(string)
  def substitution_risk?(%Value{raw: raw}), do: unescaped_sigil?(raw)

  defp unescaped_sigil?(<<>>), do: false
  defp unescaped_sigil?(<<?\\, _skipped::utf8, rest::binary>>), do: unescaped_sigil?(rest)
  defp unescaped_sigil?(<<?$, _rest::binary>>), do: true
  defp unescaped_sigil?(<<?[, _rest::binary>>), do: true
  defp unescaped_sigil?(<<_char::utf8, rest::binary>>), do: unescaped_sigil?(rest)
end
