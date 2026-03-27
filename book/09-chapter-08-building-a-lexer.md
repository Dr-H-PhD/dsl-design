\newpage

# Chapter 8: Building a Lexer

Part II gave us a complete language design for MSD: its tokens, its grammar, and its semantic rules. Now we build the machinery that turns text into meaning. The first stage in that machinery is the **lexer** — the component that reads raw characters and produces a stream of tokens.

This chapter begins with the general architecture of a lexer, introduces token representation as a concept, compares scanning strategies, and examines techniques for keyword recognition and context sensitivity. We then walk through the complete MSD lexer, tracing it character by character through a concrete example.

---

## 8.1 General Lexer Architecture

A lexer (also called a *tokeniser* or *scanner*) is the first stage in any language processing pipeline. Its job is conceptually simple: transform a flat string of characters into a structured list of tokens. Each token represents the smallest meaningful unit in the language — a keyword, an identifier, a symbol, a literal value.

The lexer's interface has two inputs and two outputs:

**Inputs:**

- **Source text**: the raw string to tokenise (the contents of a `.msd` file, for instance).

- **Filename**: an optional string used solely for error reporting — it never affects the tokenisation logic.

**Outputs:**

- **Token list**: an ordered sequence of `Token` objects representing every meaningful element in the source.

- **Error list**: a (possibly empty) list of errors encountered during scanning.

This interface establishes a clean contract. The lexer handles *characters* — whitespace, symbols, the boundaries of words and numbers. The parser, which comes next in the pipeline, handles *structure* — which tokens can follow which, how blocks nest, what constitutes a valid declaration. The lexer does not know that `entity` must be followed by an identifier and then a brace. It simply recognises `entity` as a keyword and emits the corresponding token. Structural validation belongs to the parser.

Every token carries a **source location**: the line number and column number where it was found. This information is not used by the lexer itself — it is carried forward through the pipeline so that the parser and semantic analyser can produce error messages that point to the exact position in the source file. A lexer that discards location information cripples every downstream stage.

> **Note:** Some lexers produce tokens lazily, yielding one at a time as the parser requests them. Others produce the entire list eagerly, up front. For small DSLs like MSD, eager tokenisation is simpler and perfectly adequate — the entire token list fits comfortably in memory. Lazy tokenisation becomes important for languages with very large source files or streaming input.

> **Programmer:** Go provides two ready-made approaches for building lexers. For simple DSLs, `text/scanner` offers a configurable character-class scanner that handles identifiers, integers, floats, and strings out of the box -- you configure which token types to recognise and it does the character-level work. For full control, `bufio.Scanner` with a custom `SplitFunc` lets you define your own tokenisation logic whilst handling buffered I/O efficiently. Go's own lexer in `go/scanner` is a hand-written character-by-character scanner that tracks line/column positions and inserts semicolons automatically. For a DSL like MSD, a hand-written lexer of 100--200 lines of Go gives you complete control over error reporting, context sensitivity, and token position tracking -- all critical for producing the kind of precise error messages that make a DSL pleasant to use.

---

## 8.2 Token Representation

A token is a small data object with four fields:

- **Type**: an enumeration value identifying the kind of token (`ENTITY`, `LBRACE`, `IDENTIFIER`, etc.).

- **Value**: the original text fragment from the source (`"entity"`, `"{"`, `"Student"`).

- **Line**: the 1-based line number where the token appears.
- **Column**: the 1-based column number where the token starts.

In Python, this is naturally expressed as a dataclass:

```python
@dataclass
class Token:
    type: TokenType
    value: str
    line: int
    column: int
```

The `type` field is the most important. It tells the parser *what kind* of token this is, without requiring the parser to inspect the raw text. The parser never needs to check whether a string equals `"entity"` — it checks whether the type equals `TokenType.ENTITY`. This separation between classification (the lexer's job) and structure recognition (the parser's job) keeps both components simple.

### Token type design

Token types are best represented as an enumeration. Each member names a distinct kind of token:

```python
class TokenType(Enum):
    # Keywords
    PROJECT = auto()
    ENTITY = auto()
    ASSOCIATION = auto()
    LINK = auto()

    # Symbols
    LBRACE = auto()      # {
    RBRACE = auto()      # }
    LPAREN = auto()      # (
    RPAREN = auto()      # )
    COLON = auto()       # :
    COMMA = auto()       # ,
    STAR = auto()        # *

    # Literals
    IDENTIFIER = auto()  # names: Student, id, VARCHAR, etc.
    INTEGER = auto()     # numeric literals: 100, 255, etc.
    STRING_VALUE = auto() # rest-of-line value inside project {}

    # Structural
    NEWLINE = auto()     # emitted after each source line
    EOF = auto()         # marks end of input
```

MSD has **17 token types** organised into four categories:

| Category     | Token Types                                             | Count |
|--------------|---------------------------------------------------------|-------|
| **Keywords** | `PROJECT`, `ENTITY`, `ASSOCIATION`, `LINK`              | 4     |
| **Symbols**  | `LBRACE`, `RBRACE`, `LPAREN`, `RPAREN`, `COLON`, `COMMA`, `STAR` | 7     |
| **Literals** | `IDENTIFIER`, `INTEGER`, `STRING_VALUE`                 | 3     |
| **Structural** | `NEWLINE`, `EOF`                                      | 2     |

Why use an enum rather than plain strings? Three reasons. First, the compiler (or type checker) catches misspellings — `TokenType.ENTTY` is an error, but `"ENTTY"` is a valid string. Second, enums group related values, making it easy to see the full set of token types at a glance. Third, enum comparisons are faster than string comparisons, though for a DSL this size the difference is negligible.

> **Tip:** When designing token types for your own DSL, start by listing every distinct character sequence the lexer must recognise. Group them into categories (keywords, symbols, literals, structural). If two sequences serve different purposes, they need different token types — even if they look similar. MSD's `COLON` and `STAR` are both single-character symbols, but they serve completely different roles in the grammar.

---

## 8.3 Line-by-Line vs Character-by-Character Scanning

There are two fundamental approaches to scanning source text.

### Character-by-character scanning

The traditional approach, used by most compiler textbooks, processes the entire input as a single character stream. The lexer maintains a position index into the source string and advances through it one character at a time:

```python
# Character-by-character approach (simplified)
pos = 0
while pos < len(source):
    ch = source[pos]
    if ch == '\n':
        line_num += 1
        col = 0
    # ... match tokens ...
```

This approach is universal — it works for any language, regardless of whether the language is line-oriented. However, it requires explicit newline tracking, and handling line-level constructs (comments, rest-of-line captures) requires scanning forward to find the end of the line.

### Line-by-line scanning

The alternative approach splits the input into lines first, then processes each line with an inner character loop:

```python
# Line-by-line approach (simplified)
lines = source.split("\n")
for line_num, line_text in enumerate(lines, start=1):
    col = 0
    while col < len(line_text):
        ch = line_text[col]
        # ... match tokens ...
```

For DSLs, line-by-line scanning offers several advantages:

1. **Natural comment handling.** When the lexer encounters a comment marker (`#` or `//`), it simply `break`s out of the inner loop. The rest of the line is skipped automatically. No need to scan forward searching for a newline character.

2. **Automatic NEWLINE emission.** After the inner loop completes for each line, the lexer emits a `NEWLINE` token unconditionally. Line numbers come for free from the outer loop's `enumerate`.

3. **Trivial rest-of-line capture.** When the lexer needs to capture everything from the current position to the end of the line (as MSD does for project metadata values), it simply slices the current line string: `line_text[col:]`. In a character-by-character scanner, this requires scanning forward to find the next `\n`.

4. **Simpler column tracking.** The column resets to zero at the start of each line automatically.

MSD uses line-by-line scanning. The outer loop iterates over source lines; the inner loop iterates over characters within each line:

```python
def tokenize(self, source: str, filename: str = "") -> Tuple[List[Token], List[MSDError]]:
    tokens: List[Token] = []
    errors: List[MSDError] = []

    lines = source.split("\n")
    brace_depth = 0
    in_project_block = False

    for line_num, line_text in enumerate(lines, start=1):
        col = 0
        length = len(line_text)

        while col < length:
            ch = line_text[col]
            # ... matching logic ...

        # Emit newline token after each source line
        tokens.append(Token(TokenType.NEWLINE, "\\n", line_num, length + 1))

    tokens.append(Token(TokenType.EOF, "", len(lines), 0))
    return tokens, errors
```

The line-by-line approach is not suitable for every language. Languages with multi-line string literals, block comments that span many lines, or significant indentation may be easier to handle with character-by-character scanning. But for line-oriented DSLs like MSD — where comments consume the rest of a line, metadata values span a single line, and no construct crosses a line boundary — line-by-line scanning is the natural choice.

---

## 8.4 Keyword Recognition via Identifier-to-Keyword Mapping

MSD has four keywords: `project`, `entity`, `association`, and `link`. How should the lexer recognise them?

The naive approach is to check for each keyword explicitly before checking for identifiers — a chain of `if line_text[col:col+6] == "entity"` tests. This works but is fragile: it requires careful length management, can accidentally match prefixes (is `entities` a keyword followed by `s`?), and scales poorly as the keyword count grows.

The standard technique, used by virtually every hand-written lexer, is simpler:

1. **Lex everything as an identifier.** When the lexer encounters a letter or underscore, it consumes all subsequent alphanumeric characters and underscores, producing a word string.

2. **Look up the word in a keyword table.** If the word is found, emit the corresponding keyword token. If not, emit an `IDENTIFIER` token.

The keyword table is a simple dictionary:

```python
KEYWORDS = {
    "project": TokenType.PROJECT,
    "entity": TokenType.ENTITY,
    "association": TokenType.ASSOCIATION,
    "link": TokenType.LINK,
}
```

The lexer performs a case-insensitive lookup using `word.lower()`:

```python
# Identifiers and keywords
if ch.isalpha() or ch == "_":
    start = col
    while col < length and (line_text[col].isalnum() or line_text[col] == "_"):
        col += 1
    word = line_text[start:col]

    # Case-insensitive keyword matching
    keyword_type = KEYWORDS.get(word.lower())
    if keyword_type:
        tokens.append(Token(keyword_type, word, line_num, start + 1))
        if keyword_type == TokenType.PROJECT:
            in_project_block = True
    else:
        tokens.append(Token(TokenType.IDENTIFIER, word, line_num, start + 1))
    continue
```

This approach has three important properties:

**Keywords are reserved.** Because identifiers are checked against the keyword table, you cannot name an entity `entity` or an attribute `link`. The word will always be classified as a keyword. This is a deliberate design choice — allowing keywords as identifiers creates ambiguity that complicates both the lexer and the parser.

**Adding a keyword requires only one line.** To add a new keyword `constraint`, you add one entry to the `KEYWORDS` dictionary and one member to the `TokenType` enum. No changes to the scanning logic are needed.

**Case-insensitive matching is centralised.** The `word.lower()` call in the keyword lookup is the only place where case sensitivity matters. The identifier scanning loop itself is case-agnostic — it simply consumes alphanumeric characters. If you later decide to make keywords case-sensitive, you change one line (remove `.lower()`).

---

## 8.5 Handling Context Sensitivity

Most tokens in MSD are context-free: a `{` is always a `LBRACE`, an integer is always an `INTEGER`, and the word `Student` is always an `IDENTIFIER`, regardless of where they appear. But MSD has one context-sensitive case: the **colon inside a project block**.

### The problem

Consider these two colons:

```
project {
    name: My Application    // colon inside project block
}

entity Student {
    *id: INT                // colon inside entity block
}
```

In the entity block, the colon separates an attribute name from its data type. After the colon, the lexer should continue scanning normally — it will find an `IDENTIFIER` token (`INT`).

In the project block, the colon separates a metadata key from its value. After the colon, *everything until the end of the line* is the value — including spaces, special characters, and anything that would normally be separate tokens. `My Application` should not become two `IDENTIFIER` tokens; it should become a single `STRING_VALUE` token with the value `"My Application"`.

### The solution

The lexer tracks two pieces of state:

- **`in_project_block`**: a boolean flag, set to `True` when the `project` keyword is encountered.

- **`brace_depth`**: an integer counter, incremented on `{` and decremented on `}`.

When `brace_depth` returns to zero, `in_project_block` is cleared:

```python
if ch == "}":
    tokens.append(Token(TokenType.RBRACE, "}", line_num, col + 1))
    brace_depth -= 1
    if brace_depth == 0:
        in_project_block = False
    col += 1
    continue
```

When the lexer encounters a colon, it always emits a `COLON` token. Then, if `in_project_block` is `True`, it captures the rest of the line as a `STRING_VALUE`:

```python
# Colon — context-sensitive in project blocks
if ch == ":":
    tokens.append(Token(TokenType.COLON, ":", line_num, col + 1))
    col += 1

    if in_project_block:
        # Capture rest of line as STRING_VALUE (strip leading whitespace)
        rest = line_text[col:].strip()
        # Strip trailing comment
        for comment_start in ("#", "//"):
            idx = rest.find(comment_start)
            if idx >= 0:
                rest = rest[:idx].rstrip()
        if rest:
            tokens.append(Token(TokenType.STRING_VALUE, rest, line_num, col + 1))
        break  # consumed rest of line
    continue
```

Notice the `break` after capturing the `STRING_VALUE`. Since the rest of the line has been consumed, the inner character loop ends, and the lexer moves to the next line.

Also notice the comment stripping: before emitting the `STRING_VALUE`, the lexer scans for `#` or `//` within the rest-of-line text and strips everything after the comment marker. This means you can write:

```
project {
    name: University Database  # this is a comment
}
```

And the `STRING_VALUE` will be `"University Database"`, not `"University Database  # this is a comment"`.

> **Warning:** Context sensitivity should be minimised. Every context-sensitive rule adds state to the lexer, making it harder to reason about and harder to test. MSD has exactly one context-sensitive case. If your DSL design calls for three or more, consider whether a syntax redesign could eliminate some of them. A common alternative is to use quoted strings (`name: "My Application"`) instead of rest-of-line capture, which removes the need for context sensitivity entirely — but at the cost of requiring users to type quotation marks around every metadata value.

> **Programmer:** Error reporting with precise line and column numbers is what transforms a frustrating DSL into a productive one, and Go's `token.Position` type shows the standard approach. Every token in Go's lexer carries a `token.Pos` value that can be resolved to a filename, line, and column through the `token.FileSet`. For your DSL, storing `(line, column)` on every token is cheap -- two integers per token -- and it pays dividends throughout the pipeline. The parser uses positions for error messages, the semantic analyser uses them for "did you mean?" suggestions, and IDE integrations use them for syntax highlighting and jump-to-definition. If you skip position tracking to save implementation effort, you will regret it the moment your first user reports a confusing error with no source location.

---

## 8.6 Error Detection and Reporting at the Lexical Level

The lexer is responsible for exactly one kind of error: **unexpected characters**. If the lexer encounters a character that does not begin any valid token — say, `@` or `$` — it records an error and moves on.

```python
# Unknown character
errors.append(MSDError(
    message=f"unexpected character: '{ch}'",
    line=line_num,
    column=col + 1,
    filename=filename,
))
col += 1
```

Two design principles are at work here.

**The lexer does not stop on error.** After recording the unexpected character, it advances by one character and continues scanning. This means a single lexer pass can report multiple errors. If the user accidentally writes `entity Foo @@ { *id: INT }`, the lexer will report two "unexpected character" errors (one for each `@`) but will still produce valid tokens for `entity`, `Foo`, `{`, `*`, `id`, `:`, `INT`, and `}`. The parser can then analyse the token stream and may succeed despite the lexer errors — or it may find further problems.

**The lexer does not validate.** It does not check whether `VARCAHR` is a valid data type — that is the parser's job (or the semantic analyser's). It does not check whether braces are balanced — that is the parser's job. It does not check whether an entity has a primary key — that is the semantic analyser's job. The lexer's sole concern is: "Does this character start a valid token?" If yes, consume the token. If no, report the error and skip the character.

This minimal error scope keeps the lexer simple and maintainable. Each pipeline stage handles a specific category of error:

| Stage             | Errors detected                                    |
|-------------------|----------------------------------------------------|
| **Lexer**         | Unexpected characters                              |
| **Parser**        | Structural errors: missing braces, wrong token order, unknown types |
| **Semantic analyser** | Domain errors: duplicate names, missing primary keys, unresolved references |

---

## 8.7 MSD Lexer: Complete Walkthrough

With all the pieces in place, let us trace through the complete `MSDLexer.tokenize()` method. The inner loop tests characters in the following order:

1. **Whitespace**: spaces and tabs are skipped silently.
2. **Comments**: `#` or `//` cause a `break` — the rest of the line is ignored.

3. **Symbols**: `{`, `}`, `(`, `)`, `,`, `*` each emit their corresponding token.

4. **Colon** (context-sensitive): emits `COLON`, then captures `STRING_VALUE` if inside a project block.

5. **Integers**: sequences of digits are consumed and emitted as `INTEGER`.

6. **Identifiers/keywords**: sequences starting with a letter or underscore are consumed, then checked against the keyword table.

7. **Error**: any character that reaches this point is unexpected.

This ordering matters. Comments must be checked before symbols, because `//` starts with `/`, which might otherwise be treated as an unexpected character. Symbols must be checked before identifiers, because `*` might otherwise be misinterpreted. The integer check must come before the identifier check, because digits are not valid identifier-start characters — but if a digit appeared after the identifier check, it would not match `ch.isalpha()` and would fall through to the error case.

### Token trace

Let us trace the lexer through this input:

```
entity Foo {
    *id: INT
}
```

The input has three lines. The lexer processes them one by one.

**Line 1: `entity Foo {`**

| Position | Character(s) | Action | Token emitted |
|----------|-------------|--------|---------------|
| col 0–5 | `entity` | Identifier consumed, matches keyword table | `ENTITY("entity", 1, 1)` |
| col 6 | ` ` | Whitespace skipped | — |
| col 7–9 | `Foo` | Identifier consumed, not a keyword | `IDENTIFIER("Foo", 1, 8)` |
| col 10 | ` ` | Whitespace skipped | — |
| col 11 | `{` | Symbol matched | `LBRACE("{", 1, 12)` |
| end of line | — | Automatic emission | `NEWLINE("\\n", 1, 12)` |

**Line 2: `    *id: INT`**

| Position | Character(s) | Action | Token emitted |
|----------|-------------|--------|---------------|
| col 0–3 | `    ` | Whitespace skipped | — |
| col 4 | `*` | Symbol matched | `STAR("*", 2, 5)` |
| col 5–6 | `id` | Identifier consumed, not a keyword | `IDENTIFIER("id", 2, 6)` |
| col 7 | `:` | Colon matched; `in_project_block` is `False`, so no rest-of-line capture | `COLON(":", 2, 8)` |
| col 8 | ` ` | Whitespace skipped | — |
| col 9–11 | `INT` | Identifier consumed, not a keyword | `IDENTIFIER("INT", 2, 10)` |
| end of line | — | Automatic emission | `NEWLINE("\\n", 2, 12)` |

**Line 3: `}`**

| Position | Character(s) | Action | Token emitted |
|----------|-------------|--------|---------------|
| col 0 | `}` | Symbol matched; `brace_depth` decrements to 0 | `RBRACE("}", 3, 1)` |
| end of line | — | Automatic emission | `NEWLINE("\\n", 3, 2)` |

**End of input:**

The lexer appends `EOF("", 3, 0)`.

The complete token stream is:

```
ENTITY("entity", 1, 1)
IDENTIFIER("Foo", 1, 8)
LBRACE("{", 1, 12)
NEWLINE("\\n", 1, 12)
STAR("*", 2, 5)
IDENTIFIER("id", 2, 6)
COLON(":", 2, 8)
IDENTIFIER("INT", 2, 10)
NEWLINE("\\n", 2, 12)
RBRACE("}", 3, 1)
NEWLINE("\\n", 3, 2)
EOF("", 3, 0)
```

Twelve tokens from three lines of source code. Notice that `INT` is an `IDENTIFIER`, not a keyword — the lexer does not know that `INT` is a data type. That classification happens in the parser, which checks identifiers against a set of valid type names. The lexer's vocabulary is deliberately smaller than the language's vocabulary.

### Context-sensitive trace

Now consider this input:

```
project {
    name: My App
}
```

**Line 1: `project {`**

The lexer consumes `project`, finds it in the keyword table, emits `PROJECT`, and sets `in_project_block = True`. It then emits `LBRACE` and increments `brace_depth` to 1.

**Line 2: `    name: My App`**

The lexer skips whitespace, consumes `name` as an `IDENTIFIER`, then hits the colon. It emits `COLON`. Because `in_project_block` is `True`, it captures the rest of the line: `"My App"` becomes a `STRING_VALUE` token. The inner loop `break`s.

**Line 3: `}`**

The lexer emits `RBRACE`, decrements `brace_depth` to 0, and clears `in_project_block`.

The token stream:

```
PROJECT("project", 1, 1)
LBRACE("{", 1, 9)
NEWLINE("\\n", 1, 10)
IDENTIFIER("name", 2, 5)
COLON(":", 2, 9)
STRING_VALUE("My App", 2, 11)
NEWLINE("\\n", 2, 15)
RBRACE("}", 3, 1)
NEWLINE("\\n", 3, 2)
EOF("", 3, 0)
```

Without the context-sensitive colon handling, `My` and `App` would have been emitted as two separate `IDENTIFIER` tokens, and the parser would have had to piece them back together — a far messier approach.

---

## 8.8 Design Decisions

Several design choices in the MSD lexer deserve explicit justification, as they represent trade-offs that every DSL author must consider.

### Why line-by-line scanning?

Three features of MSD make line-by-line scanning the natural choice:

- **Comments** consume the rest of a line — `break` is the simplest possible implementation.

- **NEWLINE tokens** are emitted once per source line — the outer loop's end provides the natural emission point.

- **Context-sensitive colon** captures the rest of a line as a `STRING_VALUE` — `line_text[col:]` gives us exactly the right slice.

A character-by-character scanner would need to search forward for `\n` in each of these three cases.

### Why not regular expressions?

Many lexer tutorials use regular expressions to define token patterns. For MSD, manual character matching is preferable for two reasons.

First, MSD is simple enough that the matching logic is a short sequence of `if` statements. Regular expressions would add syntactic overhead (compiling patterns, managing match groups) without reducing complexity.

Second, regular expressions cannot handle context sensitivity. The decision to capture the rest of a line as `STRING_VALUE` depends on the `in_project_block` flag, which is set by earlier tokens. A regex-based lexer would need to switch between different regex sets based on state — which is essentially a hand-written state machine with regex syntax layered on top, combining the worst of both approaches.

### Why emit NEWLINE tokens?

MSD does not use newlines as statement terminators (unlike Python, which uses them heavily). So why emit them?

The answer lies in the parser. MSD's parser uses a `_skip_newlines()` helper to advance past any NEWLINE tokens before checking for the next meaningful token. This approach is simpler than having the lexer suppress newlines entirely, because the lexer would then need to know *which* newlines matter and which do not — a structural question that belongs to the parser, not the lexer.

By emitting every newline, the lexer stays simple (emit one after each line, unconditionally) and the parser stays simple (skip them whenever they appear). The two stages agree on a protocol: the lexer emits newlines liberally, the parser ignores them uniformly.

### Why track column numbers?

Column numbers are not used by the MSD parser or semantic analyser — they are carried through the pipeline purely for error reporting. An error message that says `line 7, column 15: unexpected character: '$'` allows a text editor to jump directly to the problem. Without column numbers, the user must scan the entire line to find the offending character.

For a language like MSD where lines tend to be short, column numbers are a convenience. For languages with long lines (minified CSS, for instance), they are essential.

---

## 8.9 Exercises

**Exercise 8.1 — Block comments.**
Extend the MSD lexer to support block comments (`/* ... */`) that can span multiple lines. What additional state must the lexer track? How does this interact with the line-by-line scanning approach? Write the modified scanning logic and explain how the lexer handles an unterminated block comment (one that starts with `/*` but never has a matching `*/`).

**Exercise 8.2 — Case sensitivity.**
The MSD lexer uses `word.lower()` for keyword matching, making keywords case-insensitive: `Entity`, `ENTITY`, and `entity` are all recognised as the `ENTITY` keyword. What would change if keywords were case-sensitive? Would this simplify or complicate the lexer? What impact would it have on the user experience? Argue for one approach or the other.

**Exercise 8.3 — Calculator lexer.**
Write a lexer for a simple calculator language that supports `+`, `-`, `*`, `/`, parentheses, integers, and floating-point numbers (e.g., `3.14`). Use the line-by-line scanning approach. Your lexer should handle multi-digit numbers, decimal points, and produce meaningful errors for unexpected characters. What token types do you need?

**Exercise 8.4 — Token trace.**
Trace the MSD lexer through this input and list all tokens produced, including their types and values:

```
project {
    name: My App
}
entity X {
    *id: INT
}
```

Pay particular attention to the colon in the project block versus the colon in the entity block. How many tokens does the project block's colon produce compared to the entity block's colon?

**Exercise 8.5 — String literals.**
Suppose MSD required quoted string values in project blocks (`name: "My Application"`) instead of using rest-of-line capture. Rewrite the colon-handling code to remove context sensitivity, and add a new token type `QUOTED_STRING` with a scanning rule that handles opening and closing double quotes. What happens if the closing quote is missing? How would you report that error?

**Exercise 8.6 — Performance.**
The MSD lexer calls `source.split("\n")` at the start, creating a list of all lines. For a 10,000-line MSD file, this is perfectly fine. At what scale might this become problematic? Describe an alternative approach that processes the source incrementally without splitting it into lines up front, while still preserving the benefits of line-by-line scanning.

**Exercise 8.7 — Token location accuracy.**
The MSD lexer reports column numbers as 1-based (the first character of a line is column 1). Some tools use 0-based columns instead. What are the arguments for each convention? Which convention do most text editors and IDEs expect? Write a helper function that converts between the two representations.
