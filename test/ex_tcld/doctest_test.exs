defmodule ExTcld.DoctestTest do
  @moduledoc """
  Runs the `iex>` examples embedded in every module's documentation, so that
  the examples readers see are the examples the suite executes. `ExTcld` itself
  is covered from `ExTcldTest`.
  """
  use ExUnit.Case, async: true

  doctest ExTcld.Assignment
  doctest ExTcld.Comment
  doctest ExTcld.Decoder
  doctest ExTcld.Diagnostic
  doctest ExTcld.Dict
  doctest ExTcld.Document
  doctest ExTcld.Encoder
  doctest ExTcld.Limits
  doctest ExTcld.List
  doctest ExTcld.Value
  doctest ExTcld.Parser.Grammar
  doctest ExTcld.Parser.Lexer
end
