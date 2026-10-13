defmodule ExTcld.Assignment do
  @moduledoc """
  A `set NAME VALUE` statement.

  `set` is the only Tcl command `ExTcld` understands. That boundary is
  deliberate and permanent: supporting `set` makes real config files readable,
  while `if`, `foreach` and `source` would make this a Tcl interpreter with a
  Tcl interpreter's execution semantics and attack surface. Any other command
  is reported as `:unsupported_command` rather than skipped, so a caller is
  never silently handed a partial reading of a file.
  """

  alias ExTcld.Value

  @enforce_keys [:name, :value]
  defstruct [:name, :value, :line]

  @type t :: %__MODULE__{
          name: String.t(),
          value: Value.t(),
          line: pos_integer() | nil
        }

  @doc """
  Builds an assignment.

  ## Examples

      iex> a = ExTcld.Assignment.new("X", ExTcld.Value.new("1", :bare))
      iex> {a.name, a.value.string}
      {"X", "1"}
  """
  @spec new(String.t(), Value.t(), pos_integer() | nil) :: t()
  def new(name, %Value{} = value, line \\ nil) when is_binary(name) do
    %__MODULE__{name: name, value: value, line: line}
  end

  @doc """
  Returns true when the struct is a well-formed assignment.

  ## Examples

      iex> ExTcld.Assignment.valid?(ExTcld.Assignment.new("X", ExTcld.Value.new("1", :bare)))
      true
  """
  @spec valid?(any()) :: boolean()
  def valid?(%__MODULE__{name: n, value: v}) when is_binary(n), do: Value.valid?(v)
  def valid?(_other), do: false
end
