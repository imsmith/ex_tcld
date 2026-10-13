defmodule ExTcld.ParseError do
  @moduledoc """
  Raised by the bang variants (`ExTcld.parse!/1`, `ExTcld.List.from!/2`) when
  parsing fails.

  Carries the full diagnostic list rather than only the first problem, so that
  a caller rescuing this exception loses nothing relative to the tuple-returning
  form.
  """

  defexception [:diagnostics]

  @type t :: %__MODULE__{diagnostics: [ExTcld.Diagnostic.t()]}

  @impl Exception
  @spec exception(keyword()) :: t()
  def exception(opts) when is_list(opts) do
    %__MODULE__{diagnostics: Keyword.get(opts, :diagnostics, [])}
  end

  @impl Exception
  @spec message(t()) :: String.t()
  def message(%__MODULE__{diagnostics: []}), do: "Tcl parse failed"

  def message(%__MODULE__{diagnostics: diagnostics}) do
    detail = Enum.map_join(diagnostics, "\n  ", &format/1)
    "Tcl parse failed:\n  " <> detail
  end

  defp format(%ExTcld.Diagnostic{code: code, message: message, line: nil}) do
    "[#{code}] #{message}"
  end

  defp format(%ExTcld.Diagnostic{code: code, message: message, line: line}) do
    "[#{code}] line #{line}: #{message}"
  end
end
