defmodule ExTcld.Decoder do
  @moduledoc """
  Reduces a parsed document to native Elixir terms.

  Decoding discards comments and diagnostics and yields a plain map of variable
  name to value string. Values stay strings: Tcl has no other scalar type, and
  guessing that `"1"` means the integer `1` is exactly the kind of inference
  this library refuses to make. Callers that want a list or dict apply
  `ExTcld.List.from/2` or `ExTcld.Dict.from/2` to the string themselves.

  Later assignments to the same name win, matching Tcl execution order.
  """

  alias ExTcld.{Assignment, Document}

  @doc """
  Decodes a document to a map of name => value string.

  ## Examples

      iex> {:ok, doc} = ExTcld.parse("set A 1\\nset B {x y}")
      iex> ExTcld.Decoder.decode(doc)
      %{"A" => "1", "B" => "x y"}

      iex> {:ok, doc} = ExTcld.parse("set A 1\\nset A 2")
      iex> ExTcld.Decoder.decode(doc)
      %{"A" => "2"}
  """
  @spec decode(Document.t()) :: %{optional(String.t()) => String.t()}
  def decode(%Document{} = document) do
    document
    |> Document.assignments()
    |> Enum.reduce(%{}, fn %Assignment{name: name, value: value}, acc ->
      Map.put(acc, name, value.string)
    end)
  end
end
