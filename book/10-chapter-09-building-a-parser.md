\newpage

# Chapter 9: Building a Recursive Descent Parser

The lexer from Chapter 8 transforms raw source text into a stream of tokens. Each token carries a type, a value, and a position. But a flat sequence of tokens is not yet a *structure* — it does not tell us that `student_id` is an attribute of the `Student` entity, or that `(0,N)` is the cardinality of a particular link. That structural understanding is the parser's job.

This chapter builds a complete recursive descent parser for MSD. We start with the technique itself — why it works, why it is the most popular approach for hand-written parsers — and then construct every parsing method, from top-level dispatch down to individual type expressions. Along the way, we introduce intermediate representations, token stream navigation helpers, and a robust error recovery strategy that allows the parser to report multiple errors in a single pass.

By the end of this chapter, you will have a working parser that accepts MSD token streams and produces a clean intermediate representation ready for semantic analysis.

---

## 9.1 The Recursive Descent Technique

### One Function Per Grammar Production

The core idea of recursive descent parsing is disarmingly simple: **write one function for each production rule in the grammar**. If the grammar has a rule for `entity_block`, you write a method called `_parse_entity_block()`. If it has a rule for `attribute`, you write `_parse_attribute()`. If it has a rule for `cardinality`, you write `_parse_cardinality()`.

Each function is responsible for recognising exactly the tokens described by its grammar rule. When a rule references another rule, the function calls the corresponding method. This is where the "recursive" in "recursive descent" comes from — a method can call other methods, and those methods can call further methods, naturally following the grammar's structure from top to bottom.

Consider this simplified fragment of the MSD grammar in EBNF:

```
entity_block   = "entity" IDENTIFIER "{" { attribute } "}" ;
attribute      = [ "*" ] IDENTIFIER ":" type_expr ;
type_expr      = IDENTIFIER [ "(" INTEGER ")" ] ;
```

The recursive descent translation is almost mechanical:

```python
def _parse_entity_block(self):
    self._expect(TokenType.ENTITY)
    name_tok = self._expect(TokenType.IDENTIFIER)
    self._expect(TokenType.LBRACE)
    attributes = []
    while not self._check(TokenType.RBRACE):
        attributes.append(self._parse_attribute())
    self._expect(TokenType.RBRACE)

def _parse_attribute(self):
    is_pk = False
    if self._check(TokenType.STAR):
        self._advance()
        is_pk = True
    name_tok = self._expect(TokenType.IDENTIFIER)
    self._expect(TokenType.COLON)
    data_type, size = self._parse_type_expr()
    ...

def _parse_type_expr(self):
    type_tok = self._expect(TokenType.IDENTIFIER)
    size = None
    if self._check(TokenType.LPAREN):
        self._advance()
        size_tok = self._expect(TokenType.INTEGER)
        self._expect(TokenType.RPAREN)
    ...
```

Notice the direct correspondence. The EBNF `{ attribute }` (zero or more) becomes a `while` loop. The EBNF `[ "*" ]` (optional) becomes an `if` statement. The EBNF `"entity"` (terminal) becomes a call to `_expect()`. This mechanical mapping is precisely what makes recursive descent so appealing.

### Top-Down Parsing

Recursive descent is a **top-down** parsing technique. It begins with the start symbol — the root of the grammar — and works downward towards the terminals (individual tokens). The parser never needs to "guess and backtrack" because MSD's grammar is designed to be LL(1): at every decision point, a single token of lookahead is sufficient to determine which production to apply.

The main parsing loop embodies this top-down approach:

```python
def parse(self, source: str, filename: str = "") -> ParseResult:
    lexer = MSDLexer()
    tokens, lex_errors = lexer.tokenize(source, filename)

    self._tokens = tokens
    self._pos = 0
    self._result = ParseResult(filename=filename)
    self._result.errors.extend(lex_errors)

    self._skip_newlines()

    while not self._at_end():
        try:
            self._parse_top_level()
        except _ParsePanic:
            self._recover_to_top_level()

    return self._result
```

The loop repeatedly calls `_parse_top_level()` until every token has been consumed. Each call to `_parse_top_level()` peeks at the current token and dispatches to the appropriate handler — `_parse_entity_block()`, `_parse_association_block()`, `_parse_link_statement()`, or `_parse_project_block()`. Those handlers, in turn, call lower-level methods. The entire parse tree is constructed from the top down, one function call at a time.

### Why Recursive Descent Is Popular

Recursive descent is the most widely used technique for hand-written parsers. GCC, Clang, the Go compiler, the V8 JavaScript engine, and the Rust compiler all use variants of recursive descent. The reasons are practical:

1. **Simplicity.** The code reads like a direct translation of the grammar. Anyone who understands the grammar can read the parser, and vice versa.

2. **Control.** Every parsing decision is explicit code. You can add context-sensitive logic, custom error messages, and recovery strategies exactly where they are needed.

3. **No dependencies.** The parser is pure application code. There is no parser generator tool to learn, no build step to maintain, and no generated code to debug.

4. **Excellent error messages.** Because you control every decision point, you can craft error messages that explain exactly what the parser expected and what it found.

5. **Debuggability.** You can set breakpoints, step through the parser, and inspect the token stream at any point. Try doing that with a parser table.

> **Tip:** If your grammar is LL(1) — meaning each decision can be made by looking at a single token ahead — recursive descent is almost certainly the right choice. MSD's grammar is LL(1) by design: the first token of any top-level declaration (`entity`, `association`, `link`, `project`) immediately identifies the construct type.

> **Programmer:** Recursive descent parsing is the technique used by the Go compiler itself, and `go/parser` is the canonical reference implementation. Each grammar rule in the Go specification -- `FunctionDecl`, `IfStmt`, `ForStmt` -- has a corresponding `parseXxx` method in the parser source code. The Go team chose recursive descent over parser generators like `yacc` precisely because it gives full control over error messages and recovery. For your DSL, the same principle applies: each grammar production becomes a Go function, each `|` alternative becomes an `if`/`switch`, each `{ }` repetition becomes a `for` loop, and each `[ ]` optional becomes an `if`. Pratt parsing (operator precedence parsing) extends this approach when your DSL has expressions with infix operators -- it handles precedence and associativity elegantly within the recursive descent framework.

---

## 9.2 Intermediate Representations

### Why Not Build the Final Output Directly?

A natural question arises: why not construct the final model objects — `Entity`, `Association`, `Link` — directly during parsing? Why introduce an intermediate layer?

The answer involves separation of concerns. The parser's job is to recognise syntactic structure and report syntax errors. The builder's job (Chapter 10) is to resolve references, check semantic constraints, generate UUIDs, and construct the final model. Mixing these responsibilities creates several problems:

- **UUID generation during parsing.** Final model objects in Merisio carry UUIDs. Generating UUIDs during parsing means that a syntax error in one entity could leave orphaned UUIDs in the model. The intermediate representation avoids this: no UUIDs exist until the entire parse succeeds.

- **Dependency on the model layer.** If the parser imports and constructs `Entity` objects directly, it becomes tightly coupled to the model layer. Changes to the model (adding fields, changing constructors) break the parser. The intermediate dataclasses are simple, stable, and owned by the parser module.

- **Error recovery.** When the parser encounters an error and skips tokens, a partially constructed model object is in an inconsistent state. An intermediate dataclass can safely represent partial data — it is just a container of strings and integers, with no invariants to violate.

- **Testability.** Testing the parser in isolation is straightforward when it produces simple dataclasses. You do not need to set up a full project model, mock UUID generators, or wire up layout algorithms just to verify that an entity block parses correctly.

### The Parsed Dataclasses

The MSD parser produces four intermediate dataclasses, each mirroring a grammar construct:

```python
@dataclass
class ParsedAttribute:
    name: str
    data_type: str
    size: Optional[int] = None
    is_primary_key: bool = False
    line: int = 0
    column: int = 0

@dataclass
class ParsedEntity:
    name: str
    attributes: List[ParsedAttribute] = field(default_factory=list)
    line: int = 0
    column: int = 0

@dataclass
class ParsedAssociation:
    name: str
    attributes: List[ParsedAttribute] = field(default_factory=list)
    line: int = 0
    column: int = 0

@dataclass
class ParsedLink:
    entity_name: str
    cardinality_min: str = "0"
    cardinality_max: str = "N"
    association_name: str = ""
    line: int = 0
    column: int = 0

@dataclass
class ParsedMetadata:
    name: str = ""
    author: str = ""
    description: str = ""
```

Notice several deliberate design choices. First, every dataclass carries `line` and `column` fields. These are not needed for the data model — they exist purely so that later stages (the builder, the error reporter) can point back to the source location. Second, `ParsedLink` stores entity and association names as **strings**, not as object references or UUIDs. Name resolution happens later, in the builder. Third, cardinalities are stored as strings (`"0"`, `"1"`, `"N"`), not as enums or integers. The parser validates that the values are legal, but it does not interpret them further.

### ParseResult: The Container

All parsed data flows into a single container:

```python
@dataclass
class ParseResult:
    entities: List[ParsedEntity] = field(default_factory=list)
    associations: List[ParsedAssociation] = field(default_factory=list)
    links: List[ParsedLink] = field(default_factory=list)
    metadata: Optional[ParsedMetadata] = None
    errors: List[MSDError] = field(default_factory=list)
    filename: str = ""

    @property
    def has_errors(self) -> bool:
        return any(e.severity == "error" for e in self.errors)
```

The `ParseResult` is the parser's single return value. It contains everything the builder needs: the parsed constructs, any metadata, the accumulated errors (from both the lexer and the parser), and the source filename for error reporting.

The `has_errors` property provides a convenient check: it returns `True` only if at least one error has severity `"error"`. Warnings (such as a size parameter on a type that does not accept one) do not prevent the build from proceeding. This distinction between errors and warnings is crucial for usability — users should be able to see warnings without losing their entire parse.

> **Note:** The `ParseResult` also carries lexer errors, forwarded from the tokenisation stage. This means the builder receives a single, unified error list from all stages of front-end processing. The user sees all problems at once, regardless of which stage detected them.

> **Programmer:** The intermediate representation pattern used here -- parsing into lightweight data structures before building the final model -- is exactly how `go/parser` works in the Go toolchain. The `go/parser` package produces an `ast.File` containing `ast.GenDecl`, `ast.FuncDecl`, and other AST node types. These are simple structs with position information and string fields, not the resolved type-checked objects that `go/types` later produces. This separation lets you test parsing independently of semantic analysis, swap in different backends (code generation, linting, formatting), and recover gracefully from errors. In Go, your intermediate types would be plain structs with exported fields, and the `ParseResult` would be a struct with slices of those types -- no interfaces, no methods, just data.

---

## 9.3 Token Stream Navigation

Every recursive descent parser needs a small set of helper methods for moving through the token stream. These helpers are the parser's fundamental operations — every parsing method is built from combinations of them. The MSD parser uses six.

### `_peek()`: Look Without Consuming

```python
def _peek(self) -> Token:
    return self._tokens[self._pos]
```

`_peek()` returns the current token without advancing the position. It is a read-only operation — the parser can call `_peek()` as many times as it likes without changing state. This is essential for making decisions: the parser examines the current token to determine which grammar rule to apply, then calls a more specific method to actually consume it.

### `_advance()`: Consume and Return

```python
def _advance(self) -> Token:
    tok = self._tokens[self._pos]
    self._pos += 1
    return tok
```

`_advance()` returns the current token and moves the position forward by one. After calling `_advance()`, the previous token is consumed — `_peek()` will now return the next token. This is the only method (along with `_expect()` and `_skip_newlines()`) that moves the position forward.

### `_check(*types)`: Test Without Consuming

```python
def _check(self, *types: TokenType) -> bool:
    return self._peek().type in types
```

`_check()` tests whether the current token matches one of the given types, returning a boolean without advancing. It is used for optional elements and loop conditions. For instance, `_check(TokenType.STAR)` tests whether the current attribute starts with a primary key marker, and `_check(TokenType.RBRACE)` tests whether the attribute list has ended.

### `_expect(*types)`: Consume or Fail

```python
def _expect(self, *types: TokenType) -> Token:
    self._skip_newlines()
    tok = self._peek()
    if tok.type in types:
        return self._advance()

    expected = " or ".join(t.name for t in types)
    self._error(f"expected {expected}, got {tok.type.name} ('{tok.value}')", tok)
    raise _ParsePanic()
```

`_expect()` is the workhorse. It asserts that the current token matches one of the expected types. If it does, the token is consumed and returned. If it does not, an error is recorded and a `_ParsePanic` exception is raised to trigger error recovery.

Note that `_expect()` calls `_skip_newlines()` before checking. This is a critical design choice: it means that newlines between tokens are transparent to the parser. Users can write entity blocks on one line or spread across many lines, and the parser handles both identically.

Also note that `_expect()` accepts **multiple** token types via `*types`. This is necessary for cardinality parsing, where the minimum value could be `0` (an `INTEGER` token) or `1` (also `INTEGER`), and the maximum value could be `1` (`INTEGER`) or `N` (an `IDENTIFIER` token). A single call `_expect(TokenType.INTEGER, TokenType.IDENTIFIER)` handles both cases.

### `_skip_newlines()`: Consume Whitespace

```python
def _skip_newlines(self):
    while not self._at_end() and self._peek().type == TokenType.NEWLINE:
        self._pos += 1
```

`_skip_newlines()` consumes all consecutive `NEWLINE` tokens at the current position. It is called at the start of `_expect()` and at various points where the parser transitions between constructs. By handling newlines explicitly rather than ignoring them in the lexer, the parser maintains the ability to use line boundaries for error recovery while keeping the parsing logic clean.

### `_at_end()`: Check for EOF

```python
def _at_end(self) -> bool:
    return self._peek().type == TokenType.EOF
```

`_at_end()` returns `True` when the parser has reached the end of the token stream. The lexer guarantees that the last token is always `EOF`, so this check is safe — `_peek()` will never read past the end of the list.

---

## 9.4 Parsing Blocks and Attributes

With the navigation helpers in place, we can build the parsing methods for MSD's block constructs. Entities and associations both follow the same pattern: a keyword, a name, an opening brace, a list of attributes, and a closing brace.

### Entity Blocks

The grammar rule for entity blocks is:

```
entity_block = "entity" IDENTIFIER "{" { attribute } "}" ;
```

The parser method follows this rule directly:

```python
def _parse_entity_block(self):
    """Parse: entity Name { attributes... }"""
    kw_tok = self._expect(TokenType.ENTITY)
    name_tok = self._expect(TokenType.IDENTIFIER)
    self._skip_newlines()
    self._expect(TokenType.LBRACE)
    self._skip_newlines()

    entity = ParsedEntity(
        name=name_tok.value,
        line=name_tok.line,
        column=name_tok.column,
    )

    while not self._check(TokenType.RBRACE) and not self._at_end():
        self._skip_newlines()
        if self._check(TokenType.RBRACE):
            break
        try:
            attr = self._parse_attribute()
            entity.attributes.append(attr)
        except _ParsePanic:
            self._recover_to_brace_or_keyword()
            if self._check(TokenType.RBRACE):
                break
        self._skip_newlines()

    self._expect(TokenType.RBRACE)
    self._result.entities.append(entity)
```

The method first expects the `entity` keyword and the entity name. It then opens the brace and enters a loop that parses attributes until a closing brace is found. The `try`/`except _ParsePanic` block around attribute parsing is the error recovery mechanism — if a single attribute fails to parse, the parser skips to the next attribute or the closing brace and continues. This is what allows the parser to report errors in multiple attributes within the same entity.

After the loop, the closing brace is consumed with `_expect(TokenType.RBRACE)`, and the completed `ParsedEntity` is appended to the result.

### Attribute Parsing

The grammar rule for attributes is:

```
attribute = [ "*" ] IDENTIFIER ":" type_expr ;
```

The parser method:

```python
def _parse_attribute(self) -> ParsedAttribute:
    """Parse: [*]name: TYPE[(size)]"""
    is_pk = False
    if self._check(TokenType.STAR):
        self._advance()
        is_pk = True

    name_tok = self._expect(TokenType.IDENTIFIER)
    self._expect(TokenType.COLON)

    data_type, size = self._parse_type_expr()

    return ParsedAttribute(
        name=name_tok.value,
        data_type=data_type,
        size=size,
        is_primary_key=is_pk,
        line=name_tok.line,
        column=name_tok.column,
    )
```

The optional `*` prefix is handled with `_check()` followed by `_advance()` — not `_expect()`, because the star is not required. The name and colon are mandatory, handled with `_expect()`. The type expression is delegated to `_parse_type_expr()`.

### Type Expressions

The grammar rule for type expressions is:

```
type_expr = IDENTIFIER [ "(" INTEGER ")" ] ;
```

The parser method performs validation beyond pure syntax:

```python
def _parse_type_expr(self) -> Tuple[str, Optional[int]]:
    """Parse: TYPE or TYPE(size)"""
    type_tok = self._expect(TokenType.IDENTIFIER)
    type_name = type_tok.value.upper()

    if type_name not in DATA_TYPES:
        self._error(
            f"unknown data type: '{type_tok.value}' "
            f"(valid types: {', '.join(sorted(DATA_TYPES))})",
            type_tok,
        )
        raise _ParsePanic()

    size = None
    if self._check(TokenType.LPAREN):
        self._advance()
        size_tok = self._expect(TokenType.INTEGER)
        size = int(size_tok.value)
        self._expect(TokenType.RPAREN)

        if type_name not in SIZED_TYPES:
            self._error(
                f"data type '{type_name}' does not accept a size parameter",
                type_tok,
                severity="warning",
            )

    return type_name, size
```

The method validates the type name against the `DATA_TYPES` set — a set of thirteen uppercase strings including `INT`, `VARCHAR`, `TEXT`, `DATE`, `BOOLEAN`, and others. If the type is unrecognised, an error is raised. If the type is valid, the method checks for an optional size parameter in parentheses. If a size is provided for a type that does not accept one (e.g., `INT(10)`), a warning is emitted — not an error, because the type itself is valid and the parser can continue.

The `DATA_TYPES` and `SIZED_TYPES` sets are defined at module level:

```python
DATA_TYPES = {
    "INT", "BIGINT", "SMALLINT",
    "VARCHAR", "CHAR", "TEXT",
    "BOOLEAN",
    "DATE", "TIME", "TIMESTAMP",
    "DECIMAL", "FLOAT", "DOUBLE",
}

SIZED_TYPES = {"VARCHAR", "CHAR", "DECIMAL"}
```

### Association Blocks

Association blocks follow the same pattern as entity blocks. The only difference is the keyword and the result dataclass:

```python
def _parse_association_block(self):
    """Parse: association Name { attributes... }"""
    kw_tok = self._expect(TokenType.ASSOCIATION)
    name_tok = self._expect(TokenType.IDENTIFIER)
    self._skip_newlines()
    self._expect(TokenType.LBRACE)
    self._skip_newlines()

    assoc = ParsedAssociation(
        name=name_tok.value,
        line=name_tok.line,
        column=name_tok.column,
    )

    while not self._check(TokenType.RBRACE) and not self._at_end():
        self._skip_newlines()
        if self._check(TokenType.RBRACE):
            break
        try:
            attr = self._parse_attribute()
            assoc.attributes.append(attr)
        except _ParsePanic:
            self._recover_to_brace_or_keyword()
            if self._check(TokenType.RBRACE):
                break
        self._skip_newlines()

    self._expect(TokenType.RBRACE)
    self._result.associations.append(assoc)
```

This structural similarity is not a coincidence — it reflects the domain. In MERISE, entities and associations both contain attributes. The grammar captures this shared structure, and the parser mirrors it.

---

## 9.5 Parsing Statements

Not every MSD construct is a block with braces. Link declarations are single-line statements.

### Link Statements

The grammar rule for links is:

```
link_statement = "link" IDENTIFIER cardinality IDENTIFIER ;
cardinality    = "(" min "," max ")" ;
min            = "0" | "1" ;
max            = "1" | "N" ;
```

The parser method:

```python
def _parse_link_statement(self):
    """Parse: link EntityName (min,max) AssociationName"""
    kw_tok = self._expect(TokenType.LINK)
    entity_tok = self._expect(TokenType.IDENTIFIER)

    card_min, card_max = self._parse_cardinality()

    assoc_tok = self._expect(TokenType.IDENTIFIER)

    link = ParsedLink(
        entity_name=entity_tok.value,
        cardinality_min=card_min,
        cardinality_max=card_max,
        association_name=assoc_tok.value,
        line=kw_tok.line,
        column=kw_tok.column,
    )
    self._result.links.append(link)
```

The method consumes the `link` keyword, the entity name, the cardinality (delegated to `_parse_cardinality()`), and the association name. The resulting `ParsedLink` stores names as strings — resolution to actual entity and association objects happens in the builder.

### Cardinality Parsing

Cardinality parsing is the most nuanced part of the MSD parser, because the grammar involves tokens that could be either integers or identifiers:

```python
def _parse_cardinality(self) -> Tuple[str, str]:
    """Parse: (min,max) where min in {0,1} and max in {1,N}"""
    self._expect(TokenType.LPAREN)
    min_tok = self._expect(TokenType.INTEGER, TokenType.IDENTIFIER)
    min_val = min_tok.value

    if min_val not in ("0", "1"):
        self._error(
            f"invalid minimum cardinality: '{min_val}' (expected 0 or 1)",
            min_tok,
        )
        raise _ParsePanic()

    self._expect(TokenType.COMMA)
    max_tok = self._expect(TokenType.INTEGER, TokenType.IDENTIFIER)
    max_val = max_tok.value.upper()

    if max_val not in ("1", "N"):
        self._error(
            f"invalid maximum cardinality: '{max_tok.value}' (expected 1 or N)",
            max_tok,
        )
        raise _ParsePanic()

    self._expect(TokenType.RPAREN)
    return min_val, max_val
```

The subtlety here is that `0` and `1` are lexed as `INTEGER` tokens, while `N` is lexed as an `IDENTIFIER` token. The lexer has no knowledge of cardinalities — it simply tokenises characters into their natural types. The parser must therefore accept both token types at each position. This is why `_expect()` accepts multiple types: `_expect(TokenType.INTEGER, TokenType.IDENTIFIER)` matches either token type.

After consuming the token, the parser validates the actual value. A minimum cardinality must be `"0"` or `"1"`. A maximum cardinality must be `"1"` or `"N"` (case-insensitive, normalised to uppercase). Any other value produces a specific, helpful error message.

> **Warning:** It would be tempting to add dedicated `ZERO`, `ONE`, and `N` token types to the lexer to simplify cardinality parsing. Resist this temptation. Those "tokens" are context-dependent — `N` is only special inside a cardinality expression, not when used as an entity name. Overloading the lexer with parser-level semantics creates fragile, context-sensitive tokenisation that is far harder to maintain.

---

## 9.6 Error Recovery in the Parser

A parser that stops at the first error is a parser that wastes its users' time. If a file has five errors, the user must fix one, re-run, fix the next, re-run, and so on through five edit-compile cycles. A good parser reports all five errors in a single pass.

### Panic-Mode Recovery

The MSD parser uses **panic-mode recovery**, the simplest strategy that produces robust results. The idea is straightforward:

1. When the parser encounters an unexpected token, it records an error.
2. It raises a lightweight `_ParsePanic` exception to unwind the call stack.
3. A handler at a higher level catches the exception.

4. The handler skips tokens until it reaches a **synchronisation point** — a position where parsing can safely resume.

5. Parsing continues from the synchronisation point.

The `_ParsePanic` exception is not a real error in the Python exception sense. It is a control flow mechanism — a way to jump from a deeply nested parsing method back to a recovery handler without threading return codes through every intermediate function:

```python
class _ParsePanic(Exception):
    """Internal exception for panic-mode error recovery."""
    pass
```

### Two Recovery Strategies

The MSD parser uses two recovery strategies at different granularities.

**Top-level recovery** handles errors between top-level declarations. When a `_ParsePanic` escapes `_parse_top_level()`, the main loop catches it and calls `_recover_to_top_level()`:

```python
def _recover_to_top_level(self):
    """Panic-mode recovery: skip to next top-level keyword or closing brace."""
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

This method skips tokens until it finds either a top-level keyword (indicating the start of a new declaration) or a closing brace (indicating the end of a block). If it finds a closing brace, it consumes it — this handles the case where an error occurred inside a block and the parser needs to skip past the block's closing delimiter.

**Attribute-level recovery** handles errors within entity and association blocks. When `_parse_attribute()` raises `_ParsePanic`, the enclosing block parser catches it and calls `_recover_to_brace_or_keyword()`:

```python
def _recover_to_brace_or_keyword(self):
    """Skip to next closing brace or top-level keyword."""
    while not self._at_end():
        tok = self._peek()
        if tok.type == TokenType.RBRACE:
            return
        if tok.type in (TokenType.ENTITY, TokenType.ASSOCIATION,
                        TokenType.LINK, TokenType.PROJECT):
            return
        if tok.type == TokenType.STAR:
            return
        # Stop at identifier followed by colon (next attribute)
        if (tok.type == TokenType.IDENTIFIER
                and self._pos + 1 < len(self._tokens)):
            next_tok = self._tokens[self._pos + 1]
            if next_tok.type == TokenType.COLON:
                return
        self._advance()
```

This method is more refined than `_recover_to_top_level()`. It recognises four synchronisation points: a closing brace (end of the block), a top-level keyword (a new declaration — the block was probably not closed), a `*` token (start of a new primary key attribute), or an identifier followed by a colon (start of a new regular attribute).

The two-level strategy means that a single bad attribute does not invalidate the entire entity. The parser reports the error, skips to the next recognisable attribute, and continues parsing. The user sees errors for every malformed attribute in a single run.

### How Recovery Works in Practice

Consider this input with an error on line 3:

```
entity Student {
    *student_id: INT
    email: BLOB
    name: VARCHAR(100)
}
```

`BLOB` is not a recognised MSD data type. Here is what happens:

1. The parser enters `_parse_entity_block()` and successfully parses the entity name and opening brace.

2. It parses `*student_id: INT` successfully.

3. It enters `_parse_attribute()` for `email: BLOB`. The `_parse_type_expr()` method finds that `BLOB` is not in `DATA_TYPES`, records an error, and raises `_ParsePanic`.

4. The `except _ParsePanic` handler in `_parse_entity_block()` calls `_recover_to_brace_or_keyword()`.

5. The recovery method advances through the token stream. It finds `name` (an `IDENTIFIER`) followed by `:` (a `COLON`) — a synchronisation point. It stops.

6. The `while` loop in `_parse_entity_block()` continues. It parses `name: VARCHAR(100)` successfully.

7. The closing brace is consumed and the entity is appended to the result.

The final `ParseResult` contains one entity (`Student`) with two attributes (`student_id` and `name`) and one error (unknown data type `BLOB` on line 3). The `email` attribute is lost — it could not be parsed — but everything else was recovered.

---

## 9.7 MSD Parser: Complete Walkthrough

Let us trace the parser through a complete MSD file, following every method call and every token consumed. This walkthrough brings together all the concepts from the preceding sections.

### Input File

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
}

link Student (0,N) enrolled_in
```

### Token Stream

The lexer produces (omitting NEWLINE tokens for clarity):

| # | Type        | Value         | Line | Col |
|---|-------------|---------------|------|-----|
| 1 | ENTITY      | `entity`      | 1    | 1   |
| 2 | IDENTIFIER  | `Student`     | 1    | 8   |
| 3 | LBRACE      | `{`           | 1    | 16  |
| 4 | STAR        | `*`           | 2    | 5   |
| 5 | IDENTIFIER  | `student_id`  | 2    | 6   |
| 6 | COLON       | `:`           | 2    | 16  |
| 7 | IDENTIFIER  | `INT`         | 2    | 18  |
| 8 | IDENTIFIER  | `name`        | 3    | 5   |
| 9 | COLON       | `:`           | 3    | 9   |
| 10| IDENTIFIER  | `VARCHAR`     | 3    | 11  |
| 11| LPAREN      | `(`           | 3    | 18  |
| 12| INTEGER     | `100`         | 3    | 19  |
| 13| RPAREN      | `)`           | 3    | 22  |
| 14| RBRACE      | `}`           | 4    | 1   |
| 15| LINK        | `link`        | 6    | 1   |
| 16| IDENTIFIER  | `Student`     | 6    | 6   |
| 17| LPAREN      | `(`           | 6    | 14  |
| 18| INTEGER     | `0`           | 6    | 15  |
| 19| COMMA       | `,`           | 6    | 16  |
| 20| IDENTIFIER  | `N`           | 6    | 17  |
| 21| RPAREN      | `)`           | 6    | 18  |
| 22| IDENTIFIER  | `enrolled_in` | 6    | 20  |
| 23| EOF         |               | 6    | 0   |

### Step-by-Step Trace

**Step 1: Main loop calls `_parse_top_level()`.**
The parser skips newlines and peeks at token #1: `ENTITY`. It dispatches to `_parse_entity_block()`.

**Step 2: `_parse_entity_block()` begins.**

- `_expect(TokenType.ENTITY)` consumes token #1 (`entity`).

- `_expect(TokenType.IDENTIFIER)` consumes token #2 (`Student`). The entity name is `"Student"`.

- `_skip_newlines()` skips any intervening newlines.
- `_expect(TokenType.LBRACE)` consumes token #3 (`{`).
- Creates `ParsedEntity(name="Student", line=1, column=8)`.
- Enters the attribute loop.

**Step 3: First attribute — `*student_id: INT`.**

- `_check(TokenType.RBRACE)` $\rightarrow$ `False`. Loop continues.
- `_parse_attribute()` is called.
  - `_check(TokenType.STAR)` $\rightarrow$ `True`. Advance consumes token #4. `is_pk = True`.
  - `_expect(TokenType.IDENTIFIER)` consumes token #5 (`student_id`).
  - `_expect(TokenType.COLON)` consumes token #6 (`:`).
  - `_parse_type_expr()` is called.
    - `_expect(TokenType.IDENTIFIER)` consumes token #7 (`INT`). `type_name = "INT"`.
    - `"INT"` is in `DATA_TYPES`. No error.
    - `_check(TokenType.LPAREN)` $\rightarrow$ `False`. No size parameter.
    - Returns `("INT", None)`.
  - Returns `ParsedAttribute(name="student_id", data_type="INT", is_primary_key=True, ...)`.
- Attribute appended to entity.

**Step 4: Second attribute — `name: VARCHAR(100)`.**

- `_check(TokenType.RBRACE)` $\rightarrow$ `False`. Loop continues.
- `_parse_attribute()` is called.
  - `_check(TokenType.STAR)` $\rightarrow$ `False`. `is_pk = False`.
  - `_expect(TokenType.IDENTIFIER)` consumes token #8 (`name`).
  - `_expect(TokenType.COLON)` consumes token #9 (`:`).
  - `_parse_type_expr()` is called.
    - `_expect(TokenType.IDENTIFIER)` consumes token #10 (`VARCHAR`). `type_name = "VARCHAR"`.
    - `"VARCHAR"` is in `DATA_TYPES`. No error.
    - `_check(TokenType.LPAREN)` $\rightarrow$ `True`. Advance consumes token #11 (`(`).
    - `_expect(TokenType.INTEGER)` consumes token #12 (`100`). `size = 100`.
    - `_expect(TokenType.RPAREN)` consumes token #13 (`)`).
    - `"VARCHAR"` is in `SIZED_TYPES`. No warning.
    - Returns `("VARCHAR", 100)`.
  - Returns `ParsedAttribute(name="name", data_type="VARCHAR", size=100, ...)`.
- Attribute appended to entity.

**Step 5: End of entity block.**

- `_skip_newlines()` skips any newlines.
- `_check(TokenType.RBRACE)` $\rightarrow$ `True`. Loop exits.
- `_expect(TokenType.RBRACE)` consumes token #14 (`}`).
- `ParsedEntity` with two attributes appended to `self._result.entities`.

**Step 6: Main loop calls `_parse_top_level()` again.**
Skips newlines. Peeks at token #15: `LINK`. Dispatches to `_parse_link_statement()`.

**Step 7: `_parse_link_statement()` begins.**

- `_expect(TokenType.LINK)` consumes token #15 (`link`).
- `_expect(TokenType.IDENTIFIER)` consumes token #16 (`Student`).
- `_parse_cardinality()` is called.
  - `_expect(TokenType.LPAREN)` consumes token #17 (`(`).
  - `_expect(TokenType.INTEGER, TokenType.IDENTIFIER)` consumes token #18 (`0`). `min_val = "0"`.
  - `"0"` is in `("0", "1")`. Valid.
  - `_expect(TokenType.COMMA)` consumes token #19 (`,`).
  - `_expect(TokenType.INTEGER, TokenType.IDENTIFIER)` consumes token #20 (`N`). `max_val = "N"`.
  - `"N"` is in `("1", "N")`. Valid.
  - `_expect(TokenType.RPAREN)` consumes token #21 (`)`).
  - Returns `("0", "N")`.
- `_expect(TokenType.IDENTIFIER)` consumes token #22 (`enrolled_in`).
- `ParsedLink` appended to `self._result.links`.

**Step 8: Main loop checks for more declarations.**
Peeks at token #23: `EOF`. `_at_end()` returns `True`. Loop exits.

### Final ParseResult

```python
ParseResult(
    entities=[
        ParsedEntity(
            name="Student",
            attributes=[
                ParsedAttribute(name="student_id", data_type="INT",
                                size=None, is_primary_key=True,
                                line=2, column=6),
                ParsedAttribute(name="name", data_type="VARCHAR",
                                size=100, is_primary_key=False,
                                line=3, column=5),
            ],
            line=1, column=8,
        ),
    ],
    associations=[],
    links=[
        ParsedLink(entity_name="Student",
                    cardinality_min="0", cardinality_max="N",
                    association_name="enrolled_in",
                    line=6, column=1),
    ],
    metadata=None,
    errors=[],
    filename="",
)
```

No errors, no warnings. The parse result is a complete, clean intermediate representation of the source file, ready for the builder to transform into a Merisio project.

---

## 9.8 Design Decisions

Several design decisions in the MSD parser deserve explicit justification. These decisions are not unique to MSD — they arise in almost every hand-written parser.

### Why Recursive Descent Over Parser Generators?

Parser generators like ANTLR, PLY, or Lark could generate a parser from the MSD grammar automatically. Why write one by hand?

**Simplicity of the grammar.** MSD has four top-level constructs and roughly fifteen grammar rules. A recursive descent parser for this grammar is under 200 lines of code. The overhead of learning a parser generator, writing a grammar file, integrating the generated code, and debugging generated error messages would exceed the cost of writing the parser directly.

**Natural error messages.** A hand-written parser can produce error messages that read like natural English: "expected data type after ':', got '{' on line 7". A parser generator's error messages are typically generic — "unexpected token" or "parse error" — and improving them requires fighting the generator's infrastructure.

**No dependencies.** The MSD parser is pure Python. It requires no external tool, no build step, and no generated files. Anyone can read the code, set a breakpoint, and step through the parsing logic. This matters enormously for a teaching project.

**Control over recovery.** The two-level panic-mode recovery strategy (top-level and attribute-level) would be difficult to express in most parser generator frameworks. Hand-written code gives complete control over when and how the parser recovers.

### Why Intermediate Representation?

The separation between `ParsedEntity` (parser output) and `Entity` (model object) exists for clean architectural boundaries. The parser knows about tokens and grammar rules. The builder knows about UUIDs, name resolution, and model invariants. Neither needs to understand the other's concerns. If the model layer changes — adding a colour field to entities, for instance — the parser remains unchanged.

### Why Multiple Error Reporting?

A parser that reports only the first error forces users into a slow, frustrating cycle: fix one error, re-run, discover the next error, fix it, re-run. The MSD parser reports every error it can find in a single pass. The `ParseResult.errors` list may contain errors from the lexer (unexpected characters), from the parser (unexpected tokens, invalid types, invalid cardinalities), and later from the builder (duplicate names, unresolved references). The user sees all of them at once.

This is only possible because of panic-mode recovery. Without recovery, the parser would abort at the first error, and all subsequent errors would go undetected.

### Why `_ParsePanic` as an Exception?

The alternative to `_ParsePanic` is threading error states through return values. Every parsing method would return an `Optional` or a result type, and every call site would check for failure. This is feasible but verbose — it obscures the happy path with error-handling boilerplate.

`_ParsePanic` is a lightweight control flow mechanism. It unwinds the call stack to the nearest `try`/`except` handler, which performs recovery. The happy path — the normal parsing code — reads cleanly without error checks. The unhappy path — the recovery logic — is concentrated in a few well-defined handlers. This separation makes both paths easier to read, write, and test.

> **Info:** The `_ParsePanic` class is deliberately named with a leading underscore and defined at module level rather than as a public class. It is an internal implementation detail of the parser, not part of the public API. No code outside the parser module should ever catch or raise this exception.

---

## 9.9 Exercises

**Exercise 9.1 — Project Block Parsing.**
The MSD parser includes a `_parse_project_block()` method for parsing `project { key: value ... }` blocks. Write this method yourself, following the patterns established in Section 9.4. Your method should: (a) consume the `project` keyword and opening brace, (b) loop over key-value pairs where the key is an `IDENTIFIER`, followed by a `COLON`, followed by a `STRING_VALUE`, (c) populate a `ParsedMetadata` dataclass with recognised keys (`name`, `author`, `description`), (d) emit a warning for unrecognised keys, and (e) consume the closing brace. Compare your implementation with the production code.

**Exercise 9.2 — Comment Block Construct.**
Add support for a `comment` block construct to MSD: `comment { free text here }`. Write the `_parse_comment_block()` method and add it to `_parse_top_level()`. The comment block should be parsed but not stored in the `ParseResult` — it is purely for human documentation. What changes to the lexer are needed? Consider edge cases: what happens if the free text contains `}` characters?

**Exercise 9.3 — Error Trace.**
Trace the parser through this input with an error:

```
entity A {
    x: BLOB
    name: TEXT
}
```

Show which methods are called, which tokens are consumed, when `_ParsePanic` is raised, which recovery method runs, and what the final `ParseResult` contains. Include both the successfully parsed attributes and the error list.

**Exercise 9.4 — Arithmetic Expression Parser.**
Write a recursive descent parser for arithmetic expressions with `+`, `-`, `*`, `/`, parentheses, and integer literals. Handle operator precedence correctly (`*` and `/` bind tighter than `+` and `-`). Your parser should produce an abstract syntax tree using dataclasses. Hint: you will need separate rules for `expression`, `term`, and `factor`.

**Exercise 9.5 — Multi-Type `_expect()`.**
The MSD parser's `_expect()` method accepts multiple token types via `*types`. Why is this necessary for cardinality parsing? Could the grammar be redesigned to avoid this — for instance, by making `N` a keyword? What are the trade-offs of each approach?

**Exercise 9.6 — Recovery Strategy Comparison.**
The MSD parser uses two recovery strategies: `_recover_to_top_level()` and `_recover_to_brace_or_keyword()`. Design a third recovery strategy for a hypothetical MSD extension that allows nested entity blocks (entities within entities). What synchronisation points would your recovery method use? How would it interact with the existing two strategies?

**Exercise 9.7 — Parser Testing.**
Write a test function that parses the following MSD input and asserts that the `ParseResult` contains the correct entities, attributes, links, and no errors:

```
entity Book {
    *isbn: VARCHAR(13)
    title: VARCHAR(255)
}

entity Author {
    *author_id: INT
    name: VARCHAR(100)
}

association written_by {
}

link Book (1,N) written_by
link Author (0,N) written_by
```

Then write a second test function that introduces a deliberate error (e.g., an invalid data type) and asserts that the `ParseResult` contains the expected error message while still parsing all recoverable constructs. What does your test tell you about the parser's robustness?

---

## Summary

This chapter built a complete recursive descent parser for MSD — the longest and most detailed implementation chapter in the book. We covered seven key topics:

1. **The recursive descent technique** maps grammar productions to methods, uses top-down parsing with single-token lookahead, and is the most popular approach for hand-written parsers due to its simplicity, control, and debuggability.

2. **Intermediate representations** decouple the parser from the model layer. The `Parsed*` dataclasses carry no UUIDs, no references, and no invariants — they are pure data containers that the builder transforms into the final model.

3. **Token stream navigation** relies on six essential helpers: `_peek()`, `_advance()`, `_check()`, `_expect()`, `_skip_newlines()`, and `_at_end()`. These form the parser's fundamental vocabulary.

4. **Block and attribute parsing** follows the grammar rule by rule: entity blocks contain attribute lists, attributes have optional primary key markers and mandatory type expressions, and type expressions validate against a known set of data types.

5. **Statement parsing** handles link declarations and cardinality expressions, demonstrating how the parser accepts multiple token types at a single position.

6. **Error recovery** uses panic-mode recovery at two granularities — top-level and attribute-level — allowing the parser to report multiple errors per pass and to continue parsing after failures.

7. **Design decisions** justified the choice of recursive descent over parser generators, intermediate representations over direct model construction, multi-error reporting over single-error abort, and exception-based recovery over return-code threading.

In the next chapter, we move from syntax to semantics. The builder takes the `ParseResult` produced here and transforms it into a complete Merisio project — resolving names to objects, detecting duplicates, suggesting corrections for typos, and generating UUIDs for every element.
