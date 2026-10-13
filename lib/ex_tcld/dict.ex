defmodule ExTcld.Dict do
  @moduledoc """
  Tcl dict interpretation.

  A Tcl dict is an even-length list read as alternating keys and values. That
  representation permits things an Elixir map cannot hold: source ordering, and
  duplicate keys.

  `from/1` returns a map, which is what callers almost always want and which
  matches `dict get` semantics — last value wins. `to_pairs/1` preserves order
  and duplicates for callers that need the faithful reading.
  """

  alias ExTcld.{Diagnostic, List, Limits}

  @doc """
  Reads `source` as a Tcl dict.

  Duplicate keys collapse with the last occurrence winning, matching `dict get`.

  ## Examples

      iex> ExTcld.Dict.from("a 1 b 2")
      {:ok, %{"a" => "1", "b" => "2"}}

      iex> ExTcld.Dict.from("a 1 b")
      {:error, %ExTcld.Diagnostic{code: :odd_dict_length, severity: :error,
        message: "dict has an odd number of elements (3); keys and values must pair"}}
  """
  @spec from(binary(), keyword()) :: {:ok, map()} | {:error, Diagnostic.t()}
  def from(source, opts \\ []) when is_binary(source) do
    with {:ok, pairs} <- to_pairs(source, opts) do
      {:ok, Map.new(pairs)}
    end
  end

  @doc """
  Reads `source` as an ordered list of `{key, value}` pairs, preserving source
  order and duplicate keys.

  ## Examples

      iex> ExTcld.Dict.to_pairs("b 2 a 1")
      {:ok, [{"b", "2"}, {"a", "1"}]}

      iex> ExTcld.Dict.to_pairs("a 1 a 2")
      {:ok, [{"a", "1"}, {"a", "2"}]}
  """
  @spec to_pairs(binary(), keyword()) ::
          {:ok, [{String.t(), String.t()}]} | {:error, Diagnostic.t()}
  def to_pairs(source, opts \\ []) when is_binary(source) do
    limits = Keyword.get_lazy(opts, :limits, &Limits.new/0)

    with {:ok, elements} <- List.from(source, limits: limits) do
      pair_up(elements)
    end
  end

  @doc """
  Renders a map or pair list as a Tcl dict string.

  ## Examples

      iex> ExTcld.Dict.to_string(%{"a" => "1"})
      "a 1"

      iex> ExTcld.Dict.to_string([{"paths", "/a /b"}])
      "paths {/a /b}"
  """
  @spec to_string(map() | [{String.t(), String.t()}]) :: String.t()
  def to_string(dict) when is_map(dict), do: dict |> Enum.to_list() |> __MODULE__.to_string()

  def to_string(pairs) when is_list(pairs) do
    pairs
    |> Enum.flat_map(fn {key, value} -> [key, value] end)
    |> List.to_string()
  end

  defp pair_up(elements) do
    count = length(elements)

    if rem(count, 2) == 0 do
      {:ok, elements |> Enum.chunk_every(2) |> Enum.map(fn [k, v] -> {k, v} end)}
    else
      {:error,
       Diagnostic.error(
         :odd_dict_length,
         "dict has an odd number of elements (#{count}); keys and values must pair"
       )}
    end
  end
end
