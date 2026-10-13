defmodule ExTcld.Diagnostic do
  @moduledoc """
  A single problem found while parsing Tcl data.

  Diagnostics carry a severity so that callers can distinguish *this input is
  malformed* from *this input is ambiguous and I declined to guess*. The second
  case matters: `ExTcld` never performs variable or command substitution, and a
  value containing `$` or `[` is reported rather than silently treated as a
  literal.

  Errors are returned as `{:error, [t()]}`. Warnings ride along on a successful
  parse in the `:diagnostics` field of `ExTcld.Document`.

  `error/3` and `warning/3` guard `code` against the known set, so an unknown
  code is a compile-time type warning under Elixir 1.20 rather than a struct
  that no `case` downstream will ever match.
  """

  @enforce_keys [:code, :severity, :message]
  defstruct [:code, :severity, :message, :line, :column]

  # The guard list and the type below must agree. The compiler infers from the
  # guard; ExDoc and Dialyzer read the type.
  @codes [
    :unbalanced_brace,
    :unterminated_quote,
    :brace_followed_by_text,
    :quote_followed_by_text,
    :incomplete_set,
    :unsupported_command,
    :odd_dict_length,
    :substitution_not_performed,
    :limit_exceeded
  ]

  @typedoc "Machine-readable identifier for the kind of problem found."
  @type code ::
          :unbalanced_brace
          | :unterminated_quote
          | :brace_followed_by_text
          | :quote_followed_by_text
          | :incomplete_set
          | :unsupported_command
          | :odd_dict_length
          | :substitution_not_performed
          | :limit_exceeded

  @typedoc "`:error` aborts the parse; `:warning` is advisory and does not."
  @type severity :: :error | :warning

  @type t :: %__MODULE__{
          code: code(),
          severity: severity(),
          message: String.t(),
          line: pos_integer() | nil,
          column: pos_integer() | nil
        }

  @doc """
  Builds an error diagnostic.

  ## Examples

      iex> d = ExTcld.Diagnostic.error(:unbalanced_brace, "unbalanced {")
      iex> {d.severity, d.code}
      {:error, :unbalanced_brace}
  """
  @spec error(code(), String.t(), keyword()) :: t()
  def error(code, message, opts \\ []) when code in @codes and is_binary(message) do
    %__MODULE__{
      code: code,
      severity: :error,
      message: message,
      line: Keyword.get(opts, :line),
      column: Keyword.get(opts, :column)
    }
  end

  @doc """
  Builds a warning diagnostic.

  ## Examples

      iex> d = ExTcld.Diagnostic.warning(:substitution_not_performed, "saw $")
      iex> d.severity
      :warning
  """
  @spec warning(code(), String.t(), keyword()) :: t()
  def warning(code, message, opts \\ []) when code in @codes and is_binary(message) do
    %__MODULE__{
      code: code,
      severity: :warning,
      message: message,
      line: Keyword.get(opts, :line),
      column: Keyword.get(opts, :column)
    }
  end

  @doc """
  Returns true when the diagnostic aborts a parse.

  ## Examples

      iex> ExTcld.Diagnostic.error?(ExTcld.Diagnostic.error(:incomplete_set, "x"))
      true
  """
  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{severity: severity}), do: severity == :error
end
