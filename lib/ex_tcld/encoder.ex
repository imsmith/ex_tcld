defmodule ExTcld.Encoder do
  @moduledoc """
  Renders documents and plain maps back to Tcl source.

  Encoding is quoting-canonical rather than spelling-preserving: a value is
  braced when it needs to be and left bare when it does not, regardless of how
  it was originally written. Round-tripping is therefore guaranteed at the level
  of *meaning*, not of bytes — `set X "a"` re-encodes as `set X a`, which reads
  identically.

  Maps are emitted with keys sorted, so that encoding is deterministic despite
  Elixir map ordering being unspecified.
  """

  alias ExTcld.{Assignment, Comment, Document, List, Value}

  @typedoc """
  A plain map of variable name to value. Values may be any `String.Chars`
  implementation; they are rendered with `to_string/1` before quoting.
  """
  @type assignments :: %{optional(String.t()) => String.Chars.t()}

  @doc """
  Encodes a document or a plain map of name => value.

  ## Examples

      iex> {:ok, io} = ExTcld.Encoder.encode(%{"K" => "a b"})
      iex> IO.iodata_to_binary(io)
      "set K {a b}\\n"
  """
  @spec encode(Document.t() | assignments()) :: {:ok, iodata()}
  def encode(%Document{body: body}) do
    {:ok, Enum.map(body, &encode_element/1)}
  end

  def encode(map) when is_map(map) do
    io =
      map
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map(fn {key, value} -> assignment_line(key, to_string(value)) end)

    {:ok, io}
  end

  defp encode_element(%Comment{text: text}), do: ["#", text, "\n"]

  defp encode_element(%Assignment{name: name, value: %Value{string: string}}),
    do: assignment_line(name, string)

  defp assignment_line(name, string) do
    ["set ", List.quote_element(name), " ", List.quote_element(string), "\n"]
  end
end
