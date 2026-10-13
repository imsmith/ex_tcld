defmodule ExTcld.Parser.Grammar do
  @moduledoc """
  Assembles lexed words into an `ExTcld.Document`.

  The accepted grammar is deliberately tiny:

      document  := (comment | assignment)*
      comment   := '#' <to end of line>
      assignment := 'set' word word <end of command>

  `set` is the only command. Encountering any other command is an error rather
  than a skip, because silently ignoring `foreach` would hand the caller a
  partial reading of a file while implying it was complete.

  A `#` is a comment only where a command would start. Anywhere else it is data,
  so `set H a#b` assigns the literal string `a#b`.
  """

  alias ExTcld.{Assignment, Comment, Diagnostic, Document, Limits, Value}
  alias ExTcld.Parser.Lexer

  @doc """
  Parses a whole document.

  Returns `{:ok, document}` where `document.diagnostics` holds any warnings, or
  `{:error, diagnostics}` if anything fatal was found.

  ## Examples

      iex> {:ok, doc} = ExTcld.Parser.Grammar.parse("set A 1", ExTcld.Limits.new())
      iex> length(doc.body)
      1
  """
  @spec parse(binary(), Limits.t()) ::
          {:ok, Document.t()} | {:error, [Diagnostic.t()]}
  def parse(source, %Limits{} = limits) when is_binary(source) do
    case Limits.check_size(source, limits) do
      :ok -> walk(source, 1, [], [], limits)
      {:error, diagnostic} -> {:error, [diagnostic]}
    end
  end

  defp walk(source, line, body, warnings, limits) do
    {source, line} = skip_blanks(source, line)

    case source do
      <<>> ->
        {:ok, Document.new(Enum.reverse(body), Enum.reverse(warnings))}

      <<?#, rest::binary>> ->
        {text, rest} = take_line(rest, [])
        walk(rest, line, [Comment.new(text, line) | body], warnings, limits)

      _other ->
        parse_command(source, line, body, warnings, limits)
    end
  end

  defp parse_command(source, line, body, warnings, limits) do
    case Lexer.scan_word(source, limits) do
      {:ok, %Value{string: "set"}, rest} ->
        parse_set(rest, line, body, warnings, limits)

      {:ok, %Value{string: other}, _rest} ->
        {:error,
         [
           Diagnostic.error(
             :unsupported_command,
             "unsupported command #{inspect(other)}; ExTcld understands only `set`",
             line: line
           )
         ]}

      {:error, diagnostic} ->
        {:error, [%{diagnostic | line: diagnostic.line || line}]}
    end
  end

  defp parse_set(source, line, body, warnings, limits) do
    with {:ok, name_value, rest} <- scan_required(source, line, "variable name"),
         {:ok, value, rest} <- scan_required(rest, line, "value"),
         :ok <- expect_command_end(rest, line) do
      assignment = Assignment.new(name_value.string, value, line)
      warnings = collect_warning(value, line, warnings)
      walk(rest, line, [assignment | body], warnings, limits)
    end
  end

  defp scan_required(source, line, what) do
    case skip_spaces(source) do
      <<>> ->
        {:error, [Diagnostic.error(:incomplete_set, "`set` is missing its #{what}", line: line)]}

      <<?\n, _rest::binary>> ->
        {:error, [Diagnostic.error(:incomplete_set, "`set` is missing its #{what}", line: line)]}

      trimmed ->
        case Lexer.scan_word(trimmed, Limits.new()) do
          {:ok, value, rest} -> {:ok, value, rest}
          {:error, diagnostic} -> {:error, [%{diagnostic | line: diagnostic.line || line}]}
        end
    end
  end

  defp expect_command_end(source, line) do
    case skip_spaces(source) do
      <<>> ->
        :ok

      <<?\n, _rest::binary>> ->
        :ok

      <<?;, _rest::binary>> ->
        :ok

      <<?\r, _rest::binary>> ->
        :ok

      _extra ->
        {:error,
         [Diagnostic.error(:incomplete_set, "`set` takes exactly two arguments", line: line)]}
    end
  end

  defp collect_warning(%Value{} = value, line, warnings) do
    if Lexer.substitution_risk?(value) do
      [
        Diagnostic.warning(
          :substitution_not_performed,
          "value contains `$` or `[`; ExTcld does not substitute and treated it literally",
          line: line
        )
        | warnings
      ]
    else
      warnings
    end
  end

  # --- whitespace ---------------------------------------------------------

  defp skip_blanks(<<?\n, rest::binary>>, line), do: skip_blanks(rest, line + 1)
  defp skip_blanks(<<?;, rest::binary>>, line), do: skip_blanks(rest, line)

  defp skip_blanks(<<char::utf8, rest::binary>> = source, line) do
    if Lexer.whitespace?(char), do: skip_blanks(rest, line), else: {source, line}
  end

  defp skip_blanks(<<>>, line), do: {<<>>, line}

  defp skip_spaces(<<char::utf8, rest::binary>> = source) when char != ?\n do
    if Lexer.whitespace?(char), do: skip_spaces(rest), else: source
  end

  defp skip_spaces(source), do: source

  defp take_line(<<>>, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), <<>>}

  defp take_line(<<?\n, _rest::binary>> = source, acc),
    do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), source}

  defp take_line(<<char::utf8, rest::binary>>, acc),
    do: take_line(rest, [<<char::utf8>> | acc])
end
