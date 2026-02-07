\newpage

# Chapter 13: Error Handling and Recovery

A DSL that only works on perfect input is of limited value. Real users make mistakes — typos, forgotten braces, invalid types, misspelt names. The quality of a DSL implementation is measured not just by what it does with correct input, but by how gracefully it handles errors. This chapter covers the complete error handling strategy: how errors are represented, how they flow through the pipeline, and how the parser recovers from syntax errors to report multiple problems in a single pass.

## 13.1 The Error Model

Every error in a DSL pipeline should be a first-class data object, not an exception thrown to the caller. This allows multiple errors to be collected, sorted, filtered, and presented together.

### Representing Errors with Metadata

MSD uses a single dataclass for all errors and warnings:

```python
@dataclass
class MSDError:
    message: str
    line: int = 0
    column: int = 0
    filename: str = ""
    severity: str = "error"  # "error" or "warning"

    def __str__(self) -> str:
        loc = self.filename or "<string>"
        if self.line:
            loc += f":{self.line}"
        return f"{loc}: {self.severity}: {self.message}"
```

Each error carries five pieces of information:

| Field | Purpose |
|-------|---------|
| `message` | Human-readable description of the problem |
| `line` | Source line number (1-based), 0 if unknown |
| `column` | Source column number (1-based), 0 if unknown |
| `filename` | Source filename, empty for string input |
| `severity` | `"error"` (fatal) or `"warning"` (informational) |

### The Compiler-Style Format

The string representation follows the convention used by GCC, Clang, and rustc:

```
schema.msd:5: error: unknown data type: 'BLOB'
<string>:3: warning: entity 'Foo' has no primary key
```

When no filename is provided (e.g. in tests), `<string>` is used as a placeholder. This format integrates naturally with text editors that can parse compiler output and jump to error locations.

> **Tip:** Use a structured error object rather than raising exceptions for user-facing errors. A list of error objects supports multiple errors, mixed severities, and unified reporting — none of which work well with exceptions.

## 13.2 Error vs Warning: When to Stop vs When to Continue

The distinction between errors and warnings has real consequences for tooling:

**Errors** (severity = `"error"`):
- The input is definitively wrong — the tool cannot produce correct output
- CLI: exit code 1, no output file generated
- GUI: critical dialog, import blocked
- Examples: unknown type, duplicate name, unresolved reference

**Warnings** (severity = `"warning"`):
- The input is suspicious but technically valid — the tool can still produce output
- CLI: printed to stderr, but exit code 0 and output file produced
- GUI: warning dialog, import proceeds
- Examples: entity without primary key, size parameter on an unsized type, unknown project property

The `ParseResult.has_errors` property checks for fatal errors only:

```python
@property
def has_errors(self) -> bool:
    return any(e.severity == "error" for e in self.errors)
```

> **Note:** When in doubt, make it a warning rather than an error. Users can always choose to treat warnings as errors (e.g. with a `--strict` flag), but they cannot downgrade errors to warnings. Starting permissive gives the tool designer flexibility.

### Design Guideline

A useful heuristic: if the tool can still produce *some* meaningful output despite the issue, it should be a warning. If the output would be wrong or incomplete, it should be an error.

## 13.3 Error Flow Through a Multi-Stage Pipeline

MSD's pipeline has three error-producing stages. Errors accumulate as data flows through:

```
Lexer
  │ errors: [lexer errors]
  ▼
Parser
  │ errors: [lexer errors] + [parser errors]
  ▼
Builder
  │ errors: [lexer errors] + [parser errors] + [builder errors]
  ▼
CLI/GUI
  │ reports all errors to user
```

Each stage copies the error list from the previous stage and appends its own:

- **Lexer** returns `(tokens, errors)`
- **Parser** starts with `self._result.errors.extend(lex_errors)`, then appends parser errors
- **Builder** starts with `errors = list(parse_result.errors)`, then appends builder errors

The final consumer — CLI or GUI — receives a single, comprehensive error list from all stages. One call to `builder.build()` returns every diagnostic from every stage.

This design has a subtle benefit: the builder copies the error list (`list(parse_result.errors)`) rather than mutating the original. The `ParseResult` remains immutable after parsing, which is important for testability.

## 13.4 Panic-Mode Recovery

Without error recovery, a parser stops at the first error:

```
entity A {
    x: BLOB       # Error — parser stops
}
entity B {
    *id: INT      # Never parsed
}
```

With panic-mode recovery, the parser reports the error and continues:

```
schema.msd:2: error: unknown data type: 'BLOB'
```

Entity A is created (with just its valid attributes), and entity B is parsed normally.

### How Panic Mode Works

1. The parser encounters an unexpected token
2. It records an `MSDError` with the error details
3. It raises `_ParsePanic` — a lightweight internal exception
4. The nearest `try/except _ParsePanic` handler catches it
5. A recovery method skips tokens until a **synchronisation point**
6. Parsing resumes from the synchronisation point

### Synchronisation Points

The parser defines two sets of synchronisation points for different contexts:

**Top-level recovery** — used when an entire declaration is malformed:
- Top-level keywords: `entity`, `association`, `link`, `project`
- Closing braces: `}`

```python
def _recover_to_top_level(self):
    while not self._at_end():
        tok = self._peek()
        if tok.type in (TokenType.ENTITY, TokenType.ASSOCIATION,
                        TokenType.LINK, TokenType.PROJECT):
            return
        if tok.type == TokenType.RBRACE:
            self._advance()
            return
        self._advance()
```

**Attribute-level recovery** — used when a single attribute fails within a block:
- Closing braces: `}`
- Top-level keywords
- Star: `*` (start of a primary key attribute)
- Identifier followed by colon (start of a non-PK attribute)

```python
def _recover_to_brace_or_keyword(self):
    while not self._at_end():
        tok = self._peek()
        if tok.type == TokenType.RBRACE:
            return
        if tok.type in (TokenType.ENTITY, TokenType.ASSOCIATION,
                        TokenType.LINK, TokenType.PROJECT):
            return
        if tok.type == TokenType.STAR:
            return
        if tok.type == TokenType.IDENTIFIER and self._pos + 1 < len(self._tokens):
            next_tok = self._tokens[self._pos + 1]
            if next_tok.type == TokenType.COLON:
                return
        self._advance()
```

The attribute-level recovery is more fine-grained: if one attribute has an invalid type, the parser skips to the next attribute and continues. The entity is still created with its valid attributes.

### Recovery Scopes

The parser has `try/except` blocks at two levels:

```python
# Top level — in the main parsing loop
while not self._at_end():
    try:
        self._parse_top_level()
    except _ParsePanic:
        self._recover_to_top_level()

# Attribute level — inside entity/association blocks
while not self._check(TokenType.RBRACE) and not self._at_end():
    try:
        attr = self._parse_attribute()
        entity.attributes.append(attr)
    except _ParsePanic:
        self._recover_to_brace_or_keyword()
        if self._check(TokenType.RBRACE):
            break
```

## 13.5 Multi-Error Reporting

The combination of error accumulation and panic-mode recovery enables multi-error reporting — the user sees all problems at once:

```
schema.msd:2: error: unknown data type: 'BLOB'
schema.msd:5: error: unknown data type: 'INVALID_TYPE'
schema.msd:8: error: unknown entity: 'Unknown'
```

This is far more productive than one-at-a-time reporting. Consider a file with five errors: without multi-error reporting, the user must run the tool five times, fixing one error per run. With multi-error reporting, they fix all five in one editing session.

### What Gets Preserved After Errors

When an error occurs, the parser does not discard everything:

- Entity A has an invalid attribute `x: BLOB` → Entity A is created with its remaining valid attributes
- Entity B follows Entity A → Entity B is parsed normally
- A link references an unknown entity → The link is skipped, but all other links are processed

> **Warning:** Panic-mode recovery can occasionally produce **cascade errors** — false errors triggered by the recovery process rather than by genuine mistakes. For example, if the parser skips past a closing brace during recovery, it might misinterpret the next construct. In practice, MSD's grammar is simple enough that cascading is rare, but always review the first error before addressing subsequent ones.

## 13.6 Error Message Quality

Error messages are part of the user experience. A clear error message is the difference between a frustrating tool and a helpful one.

### Principles

**Be specific** — name what went wrong:
```
unknown data type: 'BLOB'
```
Not: `invalid input` or `syntax error`

**Include alternatives** — tell the user what is valid:
```
unknown data type: 'BLOB' (valid types: BIGINT, BOOLEAN, CHAR, DATE,
DECIMAL, DOUBLE, FLOAT, INT, SMALLINT, TEXT, TIME, TIMESTAMP, VARCHAR)
```

**Suggest corrections** — catch typos:
```
unknown entity: 'Tourits' (did you mean 'Tourist'?)
```

**Show context** — include both expected and actual:
```
expected IDENTIFIER, got RBRACE ('}')
```

**Include location** — filename and line number:
```
schema.msd:5: error: unknown data type: 'BLOB'
```

### Anti-Patterns

- `"Syntax error"` — tells the user nothing
- `"Error on line 5"` — no description of what is wrong
- `"E0042"` — error codes without explanation
- `"Parse failed"` — no indication of where or why

## 13.7 The `_ParsePanic` Exception

```python
class _ParsePanic(Exception):
    """Internal exception for panic-mode error recovery."""
    pass
```

Key properties of `_ParsePanic`:

- **Private** — the underscore prefix signals it is not part of the public API
- **Never escapes** — always caught within the parser; the caller never sees it
- **Lightweight** — no message, no payload; the error is already recorded before raising
- **Not an error in itself** — it is a control flow mechanism, not a diagnostic

The error is recorded via `self._error()` *before* the exception is raised. The exception's sole purpose is to unwind the call stack to the nearest recovery handler.

## 13.8 MSD: Complete Error Handling Walkthrough

Consider this MSD file with multiple errors:

```
entity A {
    x: BLOB
    name: TEXT
}
entity A {
    *id: INT
}
association voyager { }
link Tourits (0,N) voyager
```

**Lexer stage**: No lexical errors — all characters are valid.

**Parser stage**:
- Line 2: `BLOB` is not a valid data type → error recorded, `_ParsePanic` raised
- Attribute-level recovery: skip to next attribute start (`name:`)
- Line 3: `name: TEXT` parsed successfully
- Entity A created with one attribute: `name: TEXT`
- Lines 4-6: second entity `A` parsed successfully

**Builder stage**:
- First entity A: registered in `entity_names`
- Second entity A: duplicate detected → error "duplicate entity name: 'A'"
- Association `voyager`: built successfully
- Link: entity name `Tourits` not found → Levenshtein search → distance 2 from `Tourist`... but `Tourist` is not defined either. No suggestion within distance 3 → error "unknown entity: 'Tourits'"

**Final error list** (3 errors, 0 warnings):
```
<string>:2: error: unknown data type: 'BLOB' (valid types: ...)
<string>:5: error: duplicate entity name: 'A'
<string>:9: error: unknown entity: 'Tourits'
```

## 13.9 Testing Error Paths

Error handling is part of the specification and must be tested as rigorously as the happy path.

### Test Categories

| Category | What to verify |
|----------|---------------|
| Unknown data types | Error message content, parsing continues |
| Invalid cardinalities | Both min and max validation |
| Missing braces | Detection and recovery |
| Multi-error reporting | Multiple errors found in one pass |
| Recovery after error | Valid constructs after errors are still parsed |
| Unknown references | Entity/association lookup errors |
| Duplicate names | Duplicate detection |
| Suggestions | "Did you mean?" appears for close matches |
| Line numbers | Errors reference the correct source line |

### Example Test

```python
def test_recovery_after_error(self, parser):
    source = """entity A {
    x: BLOB
}
entity B {
    *id: INT
}"""
    result = parser.parse(source)
    # Entity B should be parsed despite error in A
    valid_entities = [e for e in result.entities if e.name == "B"]
    assert len(valid_entities) == 1
    assert result.has_errors  # BLOB error recorded
```

This test verifies three things: the error was detected, recovery worked, and the subsequent entity was parsed correctly.

## 13.10 Exercises

**Exercise 13.1.** Design an error recovery strategy for a DSL where statements are separated by semicolons instead of newlines. What would the synchronisation points be? How would recovery differ from MSD's approach?

**Exercise 13.2.** MSD uses two severity levels: `"error"` and `"warning"`. Would adding `"info"` and `"hint"` levels be valuable? Define the semantics of each level. What changes would be needed in the CLI and GUI?

**Exercise 13.3.** Write a test that verifies the parser reports exactly three errors for this input:
```
entity A { x: BLOB }
entity A { *id: INT }
link Unknown (0,N) missing
```
Verify each error message contains the expected substring.

**Exercise 13.4.** The `_ParsePanic` exception carries no information — the error is recorded before raising. What would change if the exception carried the error object as a payload? Would that be better or worse? Argue both sides.

**Exercise 13.5.** MSD's cascade error risk is low because the grammar is simple. Design a more complex grammar (e.g. with nested blocks or expressions) where panic-mode recovery would be more likely to produce cascade errors. Propose mitigation strategies.

**Exercise 13.6.** Add a `--strict` mode to the MSD CLI that treats all warnings as errors. What changes to `cmd_parse()` are needed? Should `--strict` change the severity in the error objects, or should it change how the error list is evaluated?

**Exercise 13.7.** Compile a catalogue of error messages from a tool you use regularly (a compiler, linter, or build tool). Rate each message on specificity, actionability, and context. Identify the three best and three worst messages, and explain what makes them effective or unhelpful.
