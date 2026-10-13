defmodule ExTcld.Value do
  @moduledoc """
  A single Tcl value.

  Tcl is an *everything is a string* language: `{a b c}` is simultaneously the
  string `"a b c"` and a three-element list. List-ness and dict-ness are
  interpretations a caller applies, never properties the parser infers. This
  struct therefore stores the resolved string and records how it was written,
  so an encoder can reproduce the original spelling.

  Use `ExTcld.List.from/1` or `ExTcld.Dict.from/1` on `string` to interpret it.

  `new/3` guards `quoting` against the three spellings, so a misspelt atom is a
  compile-time type warning under Elixir 1.20, not a runtime `FunctionClauseError`.
  """

  @typedoc """
  How the value was written in source.

  * `:brace` — `{...}`, no substitution, content taken literally
  * `:quote` — `"..."`, backslash escapes applied
  * `:bare` — an unquoted word, backslash escapes applied
  """
  @type quoting :: :brace | :quote | :bare

  @enforce_keys [:string, :quoting]
  defstruct [:string, :quoting, :raw]

  @type t :: %__MODULE__{
          string: String.t(),
          quoting: quoting(),
          raw: String.t() | nil
        }

  @doc """
  Builds a value.

  ## Examples

      iex> v = ExTcld.Value.new("a b", :brace)
      iex> {v.string, v.quoting}
      {"a b", :brace}
  """
  @spec new(String.t(), quoting(), String.t() | nil) :: t()
  def new(string, quoting, raw \\ nil)
      when is_binary(string) and quoting in [:brace, :quote, :bare] do
    %__MODULE__{string: string, quoting: quoting, raw: raw}
  end

  @doc """
  Returns true when the struct is a well-formed value.

  ## Examples

      iex> ExTcld.Value.valid?(ExTcld.Value.new("a", :bare))
      true
  """
  @spec valid?(any()) :: boolean()
  def valid?(%__MODULE__{string: s, quoting: q})
      when is_binary(s) and q in [:brace, :quote, :bare],
      do: true

  def valid?(_other), do: false
end
