defmodule ExTcld.MixProject do
  @moduledoc false
  use Mix.Project

  def project do
    [
      app: :ex_tcld,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Tcl data-language parser and encoder for Elixir. No Tcl runtime required.",
      package: package(),
      source_url: "https://github.com/imsmith/ex_tcld",
      homepage_url: "https://github.com/imsmith/ex_tcld",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      licenses: ["AGPL-3.0-only"],
      links: %{"GitHub" => "https://github.com/imsmith/ex_tcld"},
      files: ~w(lib mix.exs mix.lock README.md LICENSE .formatter.exs)
    ]
  end

  # No parser-combinator dependency: Tcl's data grammar is brace-balanced, which
  # is counter-based and context-sensitive. A hand-written scanner in
  # ExTcld.Parser.Lexer is both clearer and more correct here than coaxing a PEG
  # combinator through depth tracking. Shipping an unused dep would be worse.
  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp docs do
    [
      main: "ExTcld",
      extras: ["docs/guide.md"],
      groups_for_modules: [
        "Data Model": [
          ExTcld.Document,
          ExTcld.Assignment,
          ExTcld.Value,
          ExTcld.Comment
        ],
        Interpretation: [
          ExTcld.List,
          ExTcld.Dict
        ],
        Parser: [
          ExTcld.Parser.Grammar,
          ExTcld.Parser.Lexer,
          ExTcld.Parser.CommentAttacher
        ],
        Pipeline: [
          ExTcld.Decoder,
          ExTcld.Encoder
        ],
        Diagnostics: [
          ExTcld.Diagnostic,
          ExTcld.Limits
        ]
      ]
    ]
  end
end
