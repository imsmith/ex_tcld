defmodule ExTcld.DictTest do
  @moduledoc """
  Tests for Tcl dict interpretation. A Tcl dict is an even-length list; these
  tests pin that contract, including duplicate-key and ordering behaviour that
  a plain map cannot represent.
  """
  use ExUnit.Case, async: true

  alias ExTcld.Dict

  describe "from/1" do
    test "interprets an even-length list as a map" do
      assert {:ok, %{"a" => "1", "b" => "2"}} = Dict.from("a 1 b 2")
    end

    test "an empty string is an empty dict" do
      assert {:ok, dict} = Dict.from("")
      assert dict == %{}
    end

    test "braced values are single elements" do
      assert {:ok, %{"paths" => "/a /b", "n" => "2"}} = Dict.from("paths {/a /b} n 2")
    end

    test "an odd-length list is an error" do
      assert {:error, %ExTcld.Diagnostic{code: :odd_dict_length}} = Dict.from("a 1 b")
    end

    test "propagates list errors" do
      assert {:error, %ExTcld.Diagnostic{code: :unbalanced_brace}} = Dict.from("a {1 b 2")
    end

    test "last value wins on duplicate keys, matching dict get" do
      assert {:ok, %{"a" => "2"}} = Dict.from("a 1 a 2")
    end
  end

  describe "to_pairs/1" do
    test "preserves source order" do
      assert {:ok, [{"b", "2"}, {"a", "1"}]} = Dict.to_pairs("b 2 a 1")
    end

    test "preserves duplicate keys that from/1 collapses" do
      assert {:ok, [{"a", "1"}, {"a", "2"}]} = Dict.to_pairs("a 1 a 2")
    end

    test "an odd-length list is still an error" do
      assert {:error, %ExTcld.Diagnostic{code: :odd_dict_length}} = Dict.to_pairs("a 1 b")
    end
  end

  describe "to_string/1" do
    test "renders a map as a flat even-length list" do
      assert Dict.to_string(%{"a" => "1"}) == "a 1"
    end

    test "braces values containing whitespace" do
      assert Dict.to_string(%{"paths" => "/a /b"}) == "paths {/a /b}"
    end

    test "round-trips through from/1" do
      dict = %{"a" => "1", "paths" => "/a /b", "empty" => ""}
      assert {:ok, ^dict} = dict |> Dict.to_string() |> Dict.from()
    end
  end
end
