defmodule ExTcld.Document do
  @moduledoc """
  A parsed Tcl data file: assignments and comments in source order, plus any
  non-fatal diagnostics raised while reading it.

  Body order is preserved so that `ExTcld.parse/2` followed by
  `ExTcld.encode/1` reproduces the input, comments included.

  `diagnostics` holds warnings only — anything fatal is returned as
  `{:error, [ExTcld.Diagnostic.t()]}` and no document is produced. The common
  warning is `:substitution_not_performed`, raised when a value contains `$` or
  `[` in a context where Tcl itself would substitute and `ExTcld` deliberately
  does not.

  `fetch/2` returns `{:ok, string}` or `:error`. Elixir 1.20 infers that union
  from the function body, so a `case` over it with an unreachable third clause
  is reported as a redundant clause at compile time.
  """

  alias ExTcld.{Assignment, Comment, Diagnostic}

  @type body_element :: Assignment.t() | Comment.t()

  @enforce_keys [:body]
  defstruct body: [], diagnostics: []

  @type t :: %__MODULE__{
          body: [body_element()],
          diagnostics: [Diagnostic.t()]
        }

  @doc """
  Builds a document.

  ## Examples

      iex> ExTcld.Document.new([]).body
      []
  """
  @spec new([body_element()], [Diagnostic.t()]) :: t()
  def new(body, diagnostics \\ []) when is_list(body) and is_list(diagnostics) do
    %__MODULE__{body: body, diagnostics: diagnostics}
  end

  @doc """
  Returns only the assignments, discarding comments.

  ## Examples

      iex> {:ok, doc} = ExTcld.parse("# c\\nset A 1")
      iex> [a] = ExTcld.Document.assignments(doc)
      iex> a.name
      "A"
  """
  @spec assignments(t()) :: [Assignment.t()]
  def assignments(%__MODULE__{body: body}) do
    Enum.filter(body, &match?(%Assignment{}, &1))
  end

  @doc """
  Fetches an assignment's value string by name.

  ## Examples

      iex> {:ok, doc} = ExTcld.parse("set A 1")
      iex> ExTcld.Document.fetch(doc, "A")
      {:ok, "1"}

      iex> {:ok, doc} = ExTcld.parse("set A 1")
      iex> ExTcld.Document.fetch(doc, "B")
      :error
  """
  @spec fetch(t(), String.t()) :: {:ok, String.t()} | :error
  def fetch(%__MODULE__{} = doc, name) when is_binary(name) do
    doc
    |> assignments()
    |> Enum.reverse()
    |> Enum.find(&(&1.name == name))
    |> case do
      %Assignment{value: value} -> {:ok, value.string}
      nil -> :error
    end
  end

  @doc """
  Returns true when the struct is a well-formed document.

  ## Examples

      iex> ExTcld.Document.valid?(ExTcld.Document.new([]))
      true
  """
  @spec valid?(any()) :: boolean()
  def valid?(%__MODULE__{body: b, diagnostics: d}) when is_list(b) and is_list(d), do: true
  def valid?(_other), do: false
end
