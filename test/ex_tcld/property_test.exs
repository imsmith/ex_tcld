defmodule ExTcld.PropertyTest do
  @moduledoc """
  Property-based round-trip tests.

  The central invariant of this library is that a value survives being written
  and read back:

      List.from(List.to_string(elements)) == {:ok, elements}

  Example-based tests can only assert that for cases someone thought of. The
  encoder chooses between three spellings (bare, braced, backslash-escaped)
  based on content, so the interesting failures live at the boundaries between
  those choices — unbalanced braces, trailing backslashes, embedded quotes —
  which is exactly what a generator explores and a human does not.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExTcld.Dict
  alias ExTcld.List, as: TclList

  # Characters chosen to land on every branch of quote_element/1: whitespace
  # forces quoting, braces exercise the balance check, backslashes and quotes
  # exercise the escape path, and multi-byte characters exercise the codepoint
  # rebuild.
  defp tcl_char do
    StreamData.frequency([
      {10, StreamData.string(:alphanumeric, length: 1)},
      {3, StreamData.member_of([" ", "\t", "\n"])},
      {3, StreamData.member_of(["{", "}"])},
      {2, StreamData.member_of(["\\", "\"", "[", "]", "$", "#", ";"])},
      {2, StreamData.member_of(["é", "日", "👍"])}
    ])
  end

  defp tcl_element do
    StreamData.map(StreamData.list_of(tcl_char(), max_length: 12), &Enum.join/1)
  end

  defp tcl_elements do
    StreamData.list_of(tcl_element(), max_length: 8)
  end

  defp variable_name do
    StreamData.string(:alphanumeric, min_length: 1, max_length: 8)
  end

  property "a single element survives quote_element/1 and List.from/1" do
    check all element <- tcl_element() do
      encoded = TclList.quote_element(element)

      assert {:ok, [^element]} = TclList.from(encoded),
             "failed for #{inspect(element)} encoded as #{inspect(encoded)}"
    end
  end

  property "an element list survives to_string/1 and from/1" do
    check all elements <- tcl_elements() do
      encoded = TclList.to_string(elements)

      assert {:ok, ^elements} = TclList.from(encoded),
             "failed for #{inspect(elements)} encoded as #{inspect(encoded)}"
    end
  end

  property "nested lists survive two levels of interpretation" do
    check all inner <- tcl_elements(), outer_extra <- tcl_element() do
      nested = TclList.to_string([TclList.to_string(inner), outer_extra])

      assert {:ok, [inner_encoded, ^outer_extra]} = TclList.from(nested)
      assert {:ok, ^inner} = TclList.from(inner_encoded)
    end
  end

  property "a document survives encode/1 and parse/1" do
    check all pairs <- StreamData.list_of({variable_name(), tcl_element()}, max_length: 6) do
      map = Map.new(pairs)
      {:ok, source} = ExTcld.encode_to_binary(map)

      assert {:ok, ^map} = ExTcld.decode(source),
             "failed for #{inspect(map)} encoded as #{inspect(source)}"
    end
  end

  property "a dict survives to_string/1 and from/1" do
    check all pairs <- StreamData.list_of({tcl_element(), tcl_element()}, max_length: 6) do
      map = Map.new(pairs)
      encoded = Dict.to_string(map)

      assert {:ok, ^map} = Dict.from(encoded),
             "failed for #{inspect(map)} encoded as #{inspect(encoded)}"
    end
  end

  property "parsing never crashes on arbitrary input" do
    check all source <- StreamData.string(:printable, max_length: 60) do
      case ExTcld.parse(source) do
        {:ok, %ExTcld.Document{}} -> :ok
        {:error, [_ | _]} -> :ok
      end
    end
  end

  property "list interpretation never crashes on arbitrary input" do
    check all source <- StreamData.string(:printable, max_length: 60) do
      case TclList.from(source) do
        {:ok, list} when is_list(list) -> :ok
        {:error, %ExTcld.Diagnostic{}} -> :ok
      end
    end
  end

  property "quote_element/1 always produces exactly one element" do
    check all element <- tcl_element() do
      encoded = TclList.quote_element(element)

      assert {:ok, decoded} = TclList.from(encoded)

      assert length(decoded) == 1,
             "#{inspect(element)} encoded as #{inspect(encoded)} decoded to #{inspect(decoded)}"
    end
  end
end
