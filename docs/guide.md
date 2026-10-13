# ExTcld Guide

## Why this exists

Tcl scripts are good at producing data. Elixir programs are good at consuming
it. The usual bridge between them is JSON, which means both sides carry a JSON
library and both sides pretend Tcl has types it does not have.

`ExTcld` removes that bridge. A Tcl script emits its native list or dict form;
Elixir reads it directly.

```tcl
# emit.tcl
set manifest [dict create name mytool effect read-only args {--verbose --json}]
puts $manifest
```

```elixir
{:ok, manifest} = ExTcld.Dict.from(output)
#=> %{"name" => "mytool", "effect" => "read-only", "args" => "--verbose --json"}

{:ok, args} = ExTcld.List.from(manifest["args"])
#=> ["--verbose", "--json"]
```

## The one idea you must hold

**Tcl values have no intrinsic shape.**

In JSON, `["a","b"]` is a list and `"a b"` is a string, and they are different
things. In Tcl there is only the string `a b`, which *may be read* as a
two-element list. The same bytes are both.

This is not a quirk to work around. It is the type system, and it means shape is
supplied by the reader:

```elixir
value = "a b c"

ExTcld.List.from(value)   #=> {:ok, ["a", "b", "c"]}
ExTcld.Dict.from(value)   #=> {:error, odd_dict_length}
# and as a plain string it is simply "a b c"
```

A library that guessed would be wrong roughly half the time and silent about it.
`ExTcld` makes you say which reading you want.

## The Elixir side does have types

Tcl values have no shape, but the Elixir functions that read them do, and
Elixir 1.20's type checker enforces it at compile time. `ExTcld` leans on that:
every public function guards its arguments, so the compiler infers what each
one accepts and checks your call sites against it.

```elixir
ExTcld.parse(123)
# warning: incompatible types given to ExTcld.parse/1
#   given types:         integer()
#   but expected one of: binary()

ExTcld.Value.new("x", :weird)
# warning: incompatible types given to ExTcld.Value.new/2
#   but expected one of: binary(), :bare or :brace or :quote

ExTcld.Limits.check_depth(1, %{max_depth: 1})
# warning: incompatible types given to ExTcld.Limits.check_depth/2
#   but expected one of: term(), %ExTcld.Limits{}
```

Return types are inferred too. `ExTcld.Document.fetch/2` returns `{:ok, string}`
or `:error`, and the compiler knows it, so a third clause in a `case` over the
result is reported as one that will never match.

Two things to keep straight:

- **The compiler infers from guards and bodies, not from `@spec`.** The specs
  are there for ExDoc and Dialyzer. They say the same thing the guards do, and
  if the two ever disagree the guard is what the compiler believes.
- **This is the Elixir type system, not a Tcl one.** `"1"` is still a string.
  The checker tells you that you passed an integer where a binary was expected;
  it does not tell you that a Tcl value is a number.

`ExTcld.TypeCheckTest` compiles each misuse above and asserts the warning, so
the contract is pinned by the suite rather than by prose.

## Reading a config file

Given `roots.tcl`:

```tcl
# Commentary lives outside the braces — `#` inside a braced value is data.
set ROOTS {
    {/home/imsmith/Documents        documents}
    {{/home/imsmith/Calibre Library} calibre}
}
```

Note the doubled braces on the second entry. The outer pair groups the *element*;
the inner pair protects the space inside the path. This is the single most
common Tcl data mistake, and it is why a whitespace-splitting shell loop cannot
read this file correctly.

```elixir
{:ok, doc} = ExTcld.parse(File.read!("roots.tcl"))
{:ok, raw} = ExTcld.Document.fetch(doc, "ROOTS")
{:ok, entries} = ExTcld.List.from(raw)

roots =
  Enum.map(entries, fn entry ->
    {:ok, [path, label]} = ExTcld.List.from(entry)
    {path, label}
  end)
```

Each `ExTcld.List.from/2` peels exactly one level. Nesting depth in the data is nesting
depth in your code — there is no recursive "parse it all" call, because there is
no way to know how deep the caller means to go.

## Diagnostics: errors versus warnings

Fatal problems return `{:error, diagnostics}` and produce no document.
Non-fatal ones ride along on a successful parse:

```elixir
{:ok, doc} = ExTcld.parse("set home $HOME")
doc.diagnostics
#=> [%ExTcld.Diagnostic{severity: :warning, code: :substitution_not_performed}]
```

The full set:

| Code | Severity | Meaning |
|---|---|---|
| `:unbalanced_brace` | error | `{` without `}`, or a stray `}` |
| `:unterminated_quote` | error | `"` with no closing `"` |
| `:incomplete_set` | error | `set` without a name, a value, or with extra arguments |
| `:unsupported_command` | error | a command other than `set` |
| `:odd_dict_length` | error | dict interpretation of an odd-length list |
| `:substitution_not_performed` | warning | `$` or `[` present where Tcl would have substituted |
| `:limit_exceeded` | error | depth, size or element ceiling hit |

`:substitution_not_performed` is the one worth understanding. It fires only when
substitution *would have happened in real Tcl* — so braced values never trigger
it, and neither does an escaped `\$`, because detection reads the original
spelling rather than the unescaped result.

## Writing Tcl data

`ExTcld.List.quote_element/1` decides how each element is spelled:

```elixir
ExTcld.List.quote_element("plain")   #=> "plain"
ExTcld.List.quote_element("a b")     #=> "{a b}"
ExTcld.List.quote_element("")        #=> "{}"
ExTcld.List.quote_element("a{b")     #=> "a\\{b"
```

Braces are preferred because they are unambiguous. When braces would not balance
— as in `a{b` — it falls back to backslash escaping, which always reads back
correctly even though it is uglier.

Encoding is canonical rather than byte-preserving: `set X "a"` re-encodes as
`set X a`. The meaning round-trips; the spelling may not. Comments and body
order do survive intact.

## Limits

```elixir
ExTcld.parse(source, limits: ExTcld.Limits.new(max_depth: 8, max_bytes: 100_000))
```

Defaults are depth 64, 4 MB, 100,000 elements. Tighten them when the source is
untrusted — interrogating an unknown script, say — and leave them alone for your
own config files.

## Deliberate non-goals

- **Not a Tcl interpreter.** No `if`, `foreach`, `proc`, `source`, `expr`.
- **No substitution.** `$var` and `[cmd]` are literal text, and you get told.
- **No type inference of Tcl values.** `"1"` stays a string. `"true"` stays a
  string. Elixir's compile-time type checking of the API is a different thing,
  and `ExTcld` uses it fully.
- **No schema validation.** Interpret the string, then validate in Elixir where
  you have real types.
