defmodule ExTcld.Comment do
  @moduledoc """
  A Tcl comment: a `#` appearing where a command would start, through end of
  line.

  Comments are retained in `ExTcld.Document` bodies so that parse/encode is
  lossless. A `#` anywhere other than command position is ordinary data and
  never becomes a comment — `set H a#b` assigns the three-character string
  `a#b`.
  """

  @enforce_keys [:text]
  defstruct [:text, :line]

  @type t :: %__MODULE__{text: String.t(), line: pos_integer() | nil}

  @doc """
  Builds a comment from the text following the `#`.

  ## Examples

      iex> ExTcld.Comment.new(" a note").text
      " a note"
  """
  @spec new(String.t(), pos_integer() | nil) :: t()
  def new(text, line \\ nil) when is_binary(text) do
    %__MODULE__{text: text, line: line}
  end

  @doc """
  Returns true when the struct is a well-formed comment.

  ## Examples

      iex> ExTcld.Comment.valid?(ExTcld.Comment.new("x"))
      true
  """
  @spec valid?(any()) :: boolean()
  def valid?(%__MODULE__{text: t}) when is_binary(t), do: true
  def valid?(_other), do: false
end
