defmodule ExTcld.Limits do
  @moduledoc """
  Resource ceilings applied while parsing untrusted Tcl data.

  Brace nesting is unbounded in the grammar, so a hostile input can drive
  arbitrary recursion depth. These ceilings make that a returned diagnostic
  rather than a crash. Every ceiling is overridable per call, because a trusted
  local config file and an interrogated third-party script deserve different
  budgets.

  Defaults are deliberately generous for hand-written config and tight enough
  to stop a pathological input.

  Every check matches on `%ExTcld.Limits{}`, so passing a bare map such as
  `%{max_depth: 1}` is a compile-time type warning under Elixir 1.20.
  """

  @enforce_keys [:max_depth, :max_bytes, :max_elements]
  defstruct [:max_depth, :max_bytes, :max_elements]

  @type t :: %__MODULE__{
          max_depth: pos_integer(),
          max_bytes: pos_integer(),
          max_elements: pos_integer()
        }

  @default_max_depth 64
  @default_max_bytes 4_000_000
  @default_max_elements 100_000

  @doc """
  Builds a limit set, overriding any of `:max_depth`, `:max_bytes` or
  `:max_elements`.

  ## Examples

      iex> ExTcld.Limits.new().max_depth
      64

      iex> ExTcld.Limits.new(max_depth: 4).max_depth
      4
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    %__MODULE__{
      max_depth: Keyword.get(opts, :max_depth, @default_max_depth),
      max_bytes: Keyword.get(opts, :max_bytes, @default_max_bytes),
      max_elements: Keyword.get(opts, :max_elements, @default_max_elements)
    }
  end

  @doc """
  Checks a source string against the byte ceiling.

  ## Examples

      iex> ExTcld.Limits.check_size("set A 1", ExTcld.Limits.new())
      :ok

      iex> {:error, d} = ExTcld.Limits.check_size("set A 1", ExTcld.Limits.new(max_bytes: 2))
      iex> d.code
      :limit_exceeded
  """
  @spec check_size(binary(), t()) :: :ok | {:error, ExTcld.Diagnostic.t()}
  def check_size(source, %__MODULE__{max_bytes: max}) when is_binary(source) do
    size = byte_size(source)

    if size > max do
      {:error,
       ExTcld.Diagnostic.error(
         :limit_exceeded,
         "input is #{size} bytes, exceeding the #{max}-byte ceiling"
       )}
    else
      :ok
    end
  end

  @doc """
  Checks a brace nesting depth against the depth ceiling.

  ## Examples

      iex> ExTcld.Limits.check_depth(3, ExTcld.Limits.new())
      :ok
  """
  @spec check_depth(non_neg_integer(), t()) :: :ok | {:error, ExTcld.Diagnostic.t()}
  def check_depth(depth, %__MODULE__{max_depth: max}) do
    if depth > max do
      {:error,
       ExTcld.Diagnostic.error(
         :limit_exceeded,
         "brace nesting depth #{depth} exceeds the ceiling of #{max}"
       )}
    else
      :ok
    end
  end

  @doc """
  Checks an element count against the element ceiling.

  ## Examples

      iex> ExTcld.Limits.check_elements(10, ExTcld.Limits.new())
      :ok
  """
  @spec check_elements(non_neg_integer(), t()) :: :ok | {:error, ExTcld.Diagnostic.t()}
  def check_elements(count, %__MODULE__{max_elements: max}) do
    if count > max do
      {:error,
       ExTcld.Diagnostic.error(
         :limit_exceeded,
         "element count #{count} exceeds the ceiling of #{max}"
       )}
    else
      :ok
    end
  end
end
