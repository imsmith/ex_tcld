defmodule ExTcld.List do
  @moduledoc """
  Tcl list interpretation.

  A Tcl list is not a distinct type — it is a string read a particular way.
  `"a b c"` is three elements; `"{a b} c"` is two. This module applies that
  reading, and `to_string/1` produces a string that reads back identically.

  Nesting is by repeated interpretation: an element of a list is itself a
  string that may be read as a list.

      iex> {:ok, [outer]} = ExTcld.List.from("{a {b c}}")
      iex> ExTcld.List.from(outer)
      {:ok, ["a", "b c"]}
  """

  alias ExTcld.{Diagnostic, Limits, Value}
  alias ExTcld.Parser.Lexer

  @doc """
  Reads `source` as a Tcl list, returning element strings.

  ## Options

  * `:limits` — an `ExTcld.Limits` struct. Defaults to `ExTcld.Limits.new/0`.

  ## Examples

      iex> ExTcld.List.from("a b c")
      {:ok, ["a", "b", "c"]}

      iex> ExTcld.List.from("{a b} c")
      {:ok, ["a b", "c"]}

      iex> ExTcld.List.from("")
      {:ok, []}
  """
  @spec from(binary(), keyword()) :: {:ok, [String.t()]} | {:error, Diagnostic.t()}
  def from(source, opts \\ []) when is_binary(source) do
    limits = Keyword.get_lazy(opts, :limits, &Limits.new/0)

    with :ok <- Limits.check_size(source, limits) do
      collect(source, [], limits)
    end
  end

  @doc """
  Reads `source` as a Tcl list, raising on failure.

  ## Examples

      iex> ExTcld.List.from!("a b")
      ["a", "b"]
  """
  @spec from!(binary(), keyword()) :: [String.t()]
  def from!(source, opts \\ []) when is_binary(source) do
    case from(source, opts) do
      {:ok, elements} -> elements
      {:error, diagnostic} -> raise ExTcld.ParseError, diagnostics: [diagnostic]
    end
  end

  @doc """
  Renders element strings as a Tcl list.

  Elements are braced when they contain whitespace, are empty, or would
  otherwise not read back as a single element.

  ## Examples

      iex> ExTcld.List.to_string(["a b", "c"])
      "{a b} c"

      iex> ExTcld.List.to_string(["a", "", "b"])
      "a {} b"
  """
  @spec to_string([String.t()]) :: String.t()
  def to_string(elements) when is_list(elements) do
    elements
    |> Enum.map_join(" ", &quote_element/1)
  end

  @doc """
  Quotes a single element so that it reads back as exactly one list element.

  ## Examples

      iex> ExTcld.List.quote_element("a b")
      "{a b}"

      iex> ExTcld.List.quote_element("plain")
      "plain"
  """
  @spec quote_element(String.t()) :: String.t()
  def quote_element(""), do: "{}"

  def quote_element(element) when is_binary(element) do
    cond do
      not needs_quoting?(element) -> element
      brace_safe?(element) -> "{" <> element <> "}"
      true -> escape_specials(element)
    end
  end

  # --- reading ------------------------------------------------------------

  defp collect(source, acc, limits) do
    case skip_whitespace(source) do
      <<>> ->
        {:ok, Enum.reverse(acc)}

      trimmed ->
        with :ok <- Limits.check_elements(length(acc) + 1, limits),
             {:ok, %Value{string: string}, rest} <- Lexer.scan_word(trimmed, limits) do
          collect(rest, [string | acc], limits)
        end
    end
  end

  defp skip_whitespace(<<char::utf8, rest::binary>> = source) do
    if Lexer.whitespace?(char), do: skip_whitespace(rest), else: source
  end

  defp skip_whitespace(<<>>), do: <<>>

  # --- writing ------------------------------------------------------------

  defp needs_quoting?(element) do
    String.match?(element, ~r/[\s{}"\\\[\]$]/u)
  end

  # Bracing is safe only when the braces balance AND the content will not eat
  # the closing brace. A value ending in an odd number of backslashes does eat
  # it: wrapping "\\" gives "{\}", where \} is an escaped brace and the group
  # never closes. Such values must take the backslash-escape path instead.
  defp brace_safe?(element) do
    balanced?(element) and rem(trailing_backslashes(element), 2) == 0
  end

  defp trailing_backslashes(element) do
    element
    |> String.to_charlist()
    |> Enum.reverse()
    |> Enum.take_while(&(&1 == ?\\))
    |> length()
  end

  defp balanced?(element), do: balanced?(element, 0)

  defp balanced?(<<>>, 0), do: true
  defp balanced?(<<>>, _depth), do: false
  defp balanced?(<<?\\, _skipped::utf8, rest::binary>>, depth), do: balanced?(rest, depth)
  defp balanced?(<<?{, rest::binary>>, depth), do: balanced?(rest, depth + 1)
  defp balanced?(<<?}, _rest::binary>>, 0), do: false
  defp balanced?(<<?}, rest::binary>>, depth), do: balanced?(rest, depth - 1)
  defp balanced?(<<_char::utf8, rest::binary>>, depth), do: balanced?(rest, depth)

  defp escape_specials(element) do
    element
    |> String.to_charlist()
    |> Enum.map_join("", &escape_char/1)
  end

  defp escape_char(char) when char in [?\\, ?{, ?}, ?", ?[, ?], ?$], do: <<?\\, char>>
  defp escape_char(char), do: if(Lexer.whitespace?(char), do: <<?\\, char>>, else: <<char::utf8>>)
end
