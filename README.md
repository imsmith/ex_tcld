# ExTcld

Tcl data-language parser and encoder for Elixir. **No Tcl runtime required** —
nothing here shells out to `tclsh`.

`ExTcld` reads the subset of Tcl that scripts use to *emit data*: list and dict
literals, `set` assignments, and comments. It exists so that Tcl scripts can
produce structured output that Elixir programs consume without either side
agreeing on JSON.

```elixir
{:ok, doc} = ExTcld.parse(File.read!("config/roots.tcl"))
{:ok, raw} = ExTcld.Document.fetch(doc, "ROOTS")
{:ok, pairs} = ExTcld.List.from(raw)

Enum.map(pairs, fn pair ->
  {:ok, [path, label]} = ExTcld.List.from(pair)
  {path, label}
end)
#=> [{"/home/imsmith/Calibre Library", "calibre"}, ...]
```

## Everything is a string

Tcl has one scalar type. `{a b c}` is simultaneously the string `"a b c"` and a
three-element list. Which reading is correct depends on what the caller wants,
not on anything a parser can see.

`ExTcld` therefore **never infers structure**. `parse/2` gives you strings.
`ExTcld.List.from/2` and `ExTcld.Dict.from/2` apply an interpretation when you
ask for one, and nesting is just repeated interpretation.

This also means values stay strings. `"1"` does not become `1`, because Tcl
never said it was a number.

## What it will not do

**No variable or command substitution.** `$HOME` is the five-character string
`$HOME`; `[pwd]` is five characters of literal text. Substitution means
evaluation, and evaluation means a Tcl interpreter with a Tcl interpreter's
semantics and attack surface.

Because quietly treating `$HOME` as a literal could mislead, the parser says so:

```elixir
{:ok, doc} = ExTcld.parse("set home $HOME")
doc.diagnostics
#=> [%ExTcld.Diagnostic{severity: :warning, code: :substitution_not_performed, ...}]
```

Braced values never substitute in real Tcl either, so `set home {$HOME}` raises
no warning. An escaped `\$HOME` raises none either — detection reads the
original spelling, not the unescaped result.

**`set` is the only command.** Anything else is an error, not a skip:

```elixir
ExTcld.parse("foreach x {1 2} {}")
#=> {:error, [%ExTcld.Diagnostic{code: :unsupported_command, ...}]}
```

Skipping would hand you a partial reading of a file while implying it was
complete. That boundary is permanent — supporting `set` makes real config files
readable; supporting `if`, `foreach` and `source` would make this an interpreter.

## API

| Function | Purpose |
|---|---|
| `ExTcld.parse/2` | source → `%ExTcld.Document{}` with body and diagnostics |
| `ExTcld.parse!/2` | same, raising `ExTcld.ParseError` |
| `ExTcld.decode/2` | source → `%{name => string}` |
| `ExTcld.encode/1` | document or map → iodata |
| `ExTcld.encode_to_binary/1` | document or map → binary |
| `ExTcld.List.from/2` | string → list elements |
| `ExTcld.List.to_string/1` | list elements → string |
| `ExTcld.Dict.from/2` | string → map (last duplicate key wins) |
| `ExTcld.Dict.to_pairs/2` | string → ordered pairs, duplicates preserved |
| `ExTcld.Document.fetch/2` | document, name → `{:ok, string}` or `:error` |

## Round-tripping

Encoding is quoting-**canonical**, not spelling-preserving. `set X "a"`
re-encodes as `set X a` — identical in meaning, different in bytes. Comments and
body order are preserved.

## Limits

Brace nesting is unbounded in the grammar, so untrusted input can drive
arbitrary recursion depth. `ExTcld.Limits` bounds depth (64), input size (4 MB)
and element count (100,000), and every ceiling is overridable per call:

```elixir
ExTcld.parse(source, limits: ExTcld.Limits.new(max_depth: 8))
```

Exceeding one returns a `:limit_exceeded` diagnostic rather than crashing.

## Type checking

`ExTcld` requires Elixir 1.20 and is written for its type checker. Every public
function guards its arguments, and the compiler infers contracts from those
guards and from function bodies. A wrong call is a compile-time warning in
*your* code, with no annotation needed on your side:

```text
warning: incompatible types given to ExTcld.parse/1:

    ExTcld.parse(123)

given types:

    integer()

but expected one of:

    binary()
```

The same applies to a bad `quoting` atom in `ExTcld.Value.new/3`, an unknown
code in `ExTcld.Diagnostic.error/3`, a plain map where `%ExTcld.Limits{}` is
expected, and an unreachable clause in a `case` over `ExTcld.Document.fetch/2`.

The compiler does not read `@spec`. Every public function still carries one,
for ExDoc and Dialyzer, and the specs say the same thing the guards do. The
test module `ExTcld.TypeCheckTest` compiles each of these misuses and asserts
the warning, so a loosened guard fails the suite. Every `iex>` example in the
module docs runs as a doctest.

## Installation

Requires Elixir 1.20 or later.

```elixir
def deps do
  [{:ex_tcld, "~> 0.1"}]
end
```

## License

AGPL-3.0-only. See [LICENSE](LICENSE).
