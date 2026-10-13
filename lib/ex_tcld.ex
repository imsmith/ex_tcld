defmodule ExTcld do
  @moduledoc """
  Tcl data-language parser and encoder for Elixir.

  `ExTcld` reads the subset of Tcl that scripts use to *emit data*: list and
  dict literals, `set` assignments, and comments. It requires no Tcl runtime —
  nothing here shells out to `tclsh`.

  ## Everything is a string

  Tcl has one scalar type. `{a b c}` is simultaneously the string `"a b c"` and
  a three-element list; which reading is correct depends on what the caller
  wants, not on anything the parser can see. `ExTcld` therefore never infers
  structure. `parse/2` gives you strings; `ExTcld.List.from/2` and
  `ExTcld.Dict.from/2` apply an interpretation when you ask for one.

      iex> {:ok, doc} = ExTcld.parse("set roots {{/a alpha} {/b beta}}")
      iex> {:ok, raw} = ExTcld.Document.fetch(doc, "roots")
      iex> {:ok, [first, _second]} = ExTcld.List.from(raw)
      iex> ExTcld.List.from(first)
      {:ok, ["/a", "alpha"]}

  ## What it will not do

  `ExTcld` performs **no variable or command substitution**. `$HOME` is the
  five-character string `$HOME`, and `[pwd]` is five characters of literal text.
  This is a deliberate boundary: substitution means evaluation, and evaluation
  means a Tcl interpreter with a Tcl interpreter's semantics and attack surface.

  Because silently treating `$HOME` as a literal could mislead, the parser says
  so. A value that would have substituted in real Tcl produces a
  `:substitution_not_performed` warning in the document's `:diagnostics` field
  while still parsing successfully:

      iex> {:ok, doc} = ExTcld.parse("set home $HOME")
      iex> [d] = doc.diagnostics
      iex> {d.severity, d.code}
      {:warning, :substitution_not_performed}

  Braced values never substitute in Tcl either, so they raise no warning.

  Likewise `set` is the only command understood. Anything else is an error
  rather than a skip, so a caller is never handed a partial reading that looks
  complete:

      iex> {:error, [d]} = ExTcld.parse("foreach x {1 2} {}")
      iex> d.code
      :unsupported_command

  ## Pipeline

      parse/2   source        -> {:ok, %ExTcld.Document{}}
      decode/2  source        -> {:ok, %{name => string}}
      encode/1  doc or map    -> {:ok, iodata}

  ## Type checking

  Every public function guards its arguments, so Elixir 1.20's type checker
  rejects misuse at the call site with no annotation on the caller's side:

      ExTcld.parse(123)
      # warning: incompatible types given to ExTcld.parse/1
      #   given types:         integer()
      #   but expected one of: binary()

  The compiler infers these contracts from patterns and guards, not from
  `@spec`. The specs document the same contracts for ExDoc and Dialyzer.
  `ExTcld.TypeCheckTest` pins the compiler's behaviour against this API.
  """

  alias ExTcld.{Decoder, Diagnostic, Document, Encoder, Limits}
  alias ExTcld.Parser.Grammar

  @doc """
  Parses Tcl data source into a document.

  ## Options

  * `:limits` — an `ExTcld.Limits` struct bounding nesting depth, input size and
    element count. Defaults to `ExTcld.Limits.new/0`.

  ## Examples

      iex> {:ok, doc} = ExTcld.parse("set A 1")
      iex> [assignment] = doc.body
      iex> {assignment.name, assignment.value.string}
      {"A", "1"}

      iex> {:error, [d]} = ExTcld.parse("set B {a b")
      iex> d.code
      :unbalanced_brace
  """
  @spec parse(binary(), keyword()) :: {:ok, Document.t()} | {:error, [Diagnostic.t()]}
  def parse(source, opts \\ []) when is_binary(source) do
    limits = Keyword.get_lazy(opts, :limits, &Limits.new/0)
    Grammar.parse(source, limits)
  end

  @doc """
  Parses Tcl data source, raising `ExTcld.ParseError` on failure.

  ## Examples

      iex> doc = ExTcld.parse!("set A 1")
      iex> length(doc.body)
      1
  """
  @spec parse!(binary(), keyword()) :: Document.t()
  def parse!(source, opts \\ []) when is_binary(source) do
    case parse(source, opts) do
      {:ok, document} -> document
      {:error, diagnostics} -> raise ExTcld.ParseError, diagnostics: diagnostics
    end
  end

  @doc """
  Parses and reduces to a plain map of variable name to value string.

  Comments are discarded. Values remain strings — see `ExTcld.List.from/2` and
  `ExTcld.Dict.from/2` to interpret them.

  ## Examples

      iex> ExTcld.decode("# note\\nset A 1\\nset B 2")
      {:ok, %{"A" => "1", "B" => "2"}}

      iex> {:error, [d]} = ExTcld.decode("set B {a b")
      iex> d.code
      :unbalanced_brace
  """
  @spec decode(binary(), keyword()) ::
          {:ok, %{optional(String.t()) => String.t()}} | {:error, [Diagnostic.t()]}
  def decode(source, opts \\ []) when is_binary(source) do
    with {:ok, document} <- parse(source, opts) do
      {:ok, Decoder.decode(document)}
    end
  end

  @doc """
  Encodes a document or a plain map back to Tcl source as iodata.

  ## Examples

      iex> {:ok, io} = ExTcld.encode(%{"A" => "1"})
      iex> IO.iodata_to_binary(io)
      "set A 1\\n"
  """
  @spec encode(Document.t() | Encoder.assignments()) :: {:ok, iodata()}
  def encode(document_or_map), do: Encoder.encode(document_or_map)

  @doc """
  Encodes to a binary rather than iodata.

  ## Examples

      iex> ExTcld.encode_to_binary(%{"A" => "1"})
      {:ok, "set A 1\\n"}
  """
  @spec encode_to_binary(Document.t() | Encoder.assignments()) :: {:ok, binary()}
  def encode_to_binary(document_or_map) do
    with {:ok, io} <- encode(document_or_map) do
      {:ok, IO.iodata_to_binary(io)}
    end
  end
end
