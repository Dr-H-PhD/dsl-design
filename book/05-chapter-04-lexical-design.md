\newpage

# Chapter 4: Lexical Design

Every language begins as a stream of characters. Before a parser can build structure, before a semantic analyser can check meaning, the raw text must be broken into meaningful pieces. This process -- **lexical analysis** -- is the first stage of any language implementation, and the decisions you make at this stage shape the entire character of your DSL.

This chapter explores the principles of lexical design: how to choose the tokens, keywords, symbols, and conventions that define the look and feel of a domain-specific language. We use MSD as our primary case study throughout, but draw comparisons from SQL, Python, CSS, GraphQL, and other languages to illustrate the breadth of choices available to a language designer.

## 4.1 Tokens as the Atoms of a Language

A **token** (sometimes called a **lexeme**) is the smallest meaningful unit of a language. Just as chemistry reduces matter to atoms, lexical analysis reduces source text to tokens. A **lexer** (or **tokeniser** or **scanner**) is the component responsible for this transformation: it reads a stream of characters and produces a stream of tokens.

Consider the following MSD fragment:

```
entity Student {
    *student_id: INT
}
```

To a human reader, this clearly defines an entity called `Student` with a primary key attribute `student_id` of type `INT`. But to a parser, this is meaningless until the lexer has done its work. The lexer transforms the character stream into a token stream:

| Token Type   | Value          |
|-------------|----------------|
| ENTITY      | `entity`       |
| IDENTIFIER  | `Student`      |
| LBRACE      | `{`            |
| NEWLINE     | `\n`           |
| STAR        | `*`            |
| IDENTIFIER  | `student_id`   |
| COLON       | `:`            |
| IDENTIFIER  | `INT`          |
| NEWLINE     | `\n`           |
| RBRACE      | `}`            |
| NEWLINE     | `\n`           |
| EOF         |                |

Several things are worth noting. First, whitespace has been consumed -- it served only to separate tokens and carries no further meaning. Second, the keyword `entity` has been recognised as a special token type (ENTITY) rather than a generic identifier. Third, each token records its position (line and column), which will be essential for error reporting later.

Why does lexical design matter? Because the tokens you choose define the **look and feel** of your language. They determine what users type, what they read, and how they think about the language. A language that uses `begin`/`end` for blocks feels fundamentally different from one that uses `{`/`}`, even if the two are semantically identical. The lexical layer is where aesthetics meets engineering.

> **Tip:** Think of lexical design as the typography of your language. Just as a book's typeface affects readability without changing the content, your token choices affect usability without changing the language's expressive power.

## 4.2 Keywords

**Keywords** (or **reserved words**) are identifiers that have been given special meaning by the language. When the lexer encounters the character sequence `entity`, it does not produce a generic IDENTIFIER token -- it produces an ENTITY token, because `entity` is a keyword.

### How Many Keywords?

The number of keywords is a strong signal of a language's complexity. Fewer keywords generally mean a simpler language that is faster to learn:

| Language | Approximate Keyword Count | Examples                                      |
|----------|--------------------------|-----------------------------------------------|
| MSD      | 4                        | `project`, `entity`, `association`, `link`    |
| CSS      | 50+                      | `color`, `margin`, `display`, `flex`, ...     |
| Python   | 35                       | `def`, `class`, `if`, `for`, `import`, ...    |
| SQL      | 300+                     | `SELECT`, `FROM`, `WHERE`, `JOIN`, `ALTER`, ...|

MSD has exactly four keywords. This is remarkably few, even for a DSL, and it reflects the language's narrow focus: MSD describes only entities, associations, links between them, and project metadata. There is no need for control flow (`if`, `while`), data manipulation (`SELECT`, `INSERT`), or module structure (`import`, `package`). Every keyword maps directly to a concept in the MERISE modelling domain.

### Keyword Reservation

An important design decision is whether keywords are **reserved** -- that is, whether users can use a keyword as an identifier name. In MSD, keywords are reserved: you cannot name an entity `entity` or an attribute `link`. This keeps the lexer simple and avoids ambiguity, but it does restrict the user's naming freedom.

Some languages take a different approach. In PL/I (a historically significant case), no words were reserved at all, which meant that statements like `IF IF = THEN THEN THEN = ELSE ELSE ELSE = IF` were syntactically valid. This is an extreme example, but it illustrates the spectrum: full reservation at one end, no reservation at the other.

For DSLs, full keyword reservation is almost always the right choice. The keyword count is small, and the simplicity it brings to the lexer and parser far outweighs the loss of a handful of identifier names.

### Case Sensitivity for Keywords

Should `Entity`, `ENTITY`, and `entity` all be recognised as the same keyword? Languages differ:

- **Case-insensitive keywords**: SQL (`SELECT` and `select` are equivalent), MSD (`Entity` and `entity` are equivalent)
- **Case-sensitive keywords**: Python (`def` is a keyword, `Def` is not), Go, Rust, C

MSD chose case-insensitive keywords for a pragmatic reason: users coming from different backgrounds have different conventions. A French computer science student accustomed to writing `ENTITE` in uppercase might naturally type `ENTITY` or `Entity`. By accepting all casings, MSD removes a source of unnecessary errors.

The implementation is straightforward -- the lexer normalises the word to lowercase before checking the keyword table:

```python
keyword_type = KEYWORDS.get(word.lower())
```

> **Note:** Case-insensitive keywords do not imply case-insensitive identifiers. In MSD, `entity` and `ENTITY` are the same keyword, but `Student` and `student` are different entity names. This split approach -- case-insensitive keywords, case-sensitive identifiers -- is the same strategy SQL uses for its keywords versus table and column names.

### Choosing Keywords That Read Naturally

Good keywords read like natural language in context. Consider MSD's `link` keyword:

```
link Student Enrol (1,N)
```

This reads almost like an English sentence: "link Student to Enrol with cardinality (1,N)." Compare this with a hypothetical alternative:

```
rel Student Enrol (1,N)
```

The abbreviation `rel` saves two characters but sacrifices readability. In a DSL where files are typically short and written infrequently, readability should almost always win over brevity.

**Design guideline**: Choose keywords that, when read aloud in a typical statement, sound like a description of what the statement does.

## 4.3 Identifiers

**Identifiers** are user-defined names: entity names, attribute names, association names, variable names. They are the tokens that the user has full control over, and the rules you set for identifiers determine what names are legal in your language.

### Character Set Rules

Most languages allow identifiers to contain letters, digits, and underscores. The almost-universal restriction is on the **first character**: it must be a letter or underscore, not a digit. This rule exists to keep the lexer simple -- if a token starts with a digit, it is a number; if it starts with a letter or underscore, it is an identifier or keyword.

MSD follows this convention:

```python
# Start of an identifier
if ch.isalpha() or ch == "_":
    start = col
    while col < length and (line_text[col].isalnum() or line_text[col] == "_"):
        col += 1
```

This means the following are all valid MSD identifiers:

```
Student
student_id
_internal
VARCHAR
```

But these are not:

```
2ndYear       # starts with a digit
student-id    # contains a hyphen
first.name    # contains a dot
```

### Case Sensitivity for Identifiers

While MSD keywords are case-insensitive, MSD identifiers are **case-sensitive**. The entity `Student` and the entity `student` are two different things. This matches the convention of most programming languages (C, Java, Python, Go) and avoids a class of subtle bugs where `studentID` and `StudentId` might accidentally refer to the same thing.

Some DSLs choose case-insensitive identifiers -- SQL is the most prominent example, where `SELECT * FROM Students` and `SELECT * FROM students` query the same table (unless quoting is used). This can be convenient but introduces its own complications: which casing should be used in output? How do you handle user-defined names that differ only in case?

### Unicode Identifiers

Should your DSL allow Unicode characters in identifiers? Python 3, Java, and Swift all allow Unicode identifiers (`nombre_d_etudiant`, `nombre_d_etudiant`, or even `nombre_d_etudiant` with accented characters). This can be important for internationalisation -- a French user might want to write `Etudiant` with an accent (`Etudiant` vs `Etudiant`).

MSD currently restricts identifiers to ASCII letters, digits, and underscores. This is a deliberate simplification: MERISE models are typically defined with ASCII identifiers even in French-language contexts, and supporting Unicode would complicate the lexer, parser, and output generator (particularly for SQL generation, where not all databases handle Unicode identifiers identically).

### Naming Conventions

The lexer does not enforce naming conventions -- it accepts any legal identifier regardless of style. But language documentation and examples establish conventions that users tend to follow:

- **PascalCase** (`StudentEnrolment`): MSD entity and association names
- **snake_case** (`student_id`): MSD attribute names
- **camelCase** (`studentId`): Common in JavaScript, Java
- **SCREAMING_SNAKE_CASE** (`MAX_SIZE`): Constants in many languages

MSD's examples consistently use PascalCase for entity and association names and snake_case for attributes. This mirrors SQL's common convention (PascalCase table names, snake_case column names) and reinforces MSD's role as a database modelling language.

## 4.4 Literals

**Literals** are values that appear directly in source code: numbers, strings, booleans. Different DSLs need different kinds of literals, and some DSLs need very few.

### Integer Literals

MSD supports integer literals for a single purpose: specifying sizes in parameterised data types.

```
name: VARCHAR(100)
price: DECIMAL(10,2)
```

The numbers `100`, `10`, and `2` are integer literals. MSD does not need floating-point numbers, hexadecimal notation, or numeric separators -- the only use of numbers in the language is to specify sizes and precisions, which are always small positive integers.

The lexer scans integer literals with a simple loop:

```python
if ch.isdigit():
    start = col
    while col < length and line_text[col].isdigit():
        col += 1
    tokens.append(Token(TokenType.INTEGER, line_text[start:col], line_num, start + 1))
```

### String Literals

String literals are values enclosed in quotation marks. Different languages use different quoting strategies:

- **Double quotes**: `"hello"` (C, Java, JSON)
- **Single quotes**: `'hello'` (SQL, Python)
- **Backticks**: `` `hello` `` (Go raw strings, SQL identifier quoting)
- **No quotes**: Values are captured without delimiters

MSD takes an unusual approach: inside `project {}` blocks, values after the colon are captured as raw strings without any quoting:

```
project {
    name: University Database
    author: Dr. Smith
    version: 2.1
}
```

The values `University Database`, `Dr. Smith`, and `2.1` are all captured as STRING_VALUE tokens without requiring quotation marks. This works because MSD's project block has simple, single-line key-value semantics -- the value is everything from the colon to the end of the line (minus any trailing comment).

This design eliminates a common source of user errors: forgetting to close a string, using the wrong quote character, or needing to escape quotes within a value. Since project metadata values never need to span multiple lines or contain colons, the quoting-free approach is both simpler and less error-prone.

### When Does a DSL Need Literals?

Not every DSL needs every kind of literal. Consider:

| DSL          | Integer | Float | String | Boolean | Other                   |
|-------------|---------|-------|--------|---------|-------------------------|
| MSD          | Yes     | No    | Yes*   | No      | --                      |
| SQL          | Yes     | Yes   | Yes    | Yes     | Date, NULL              |
| CSS          | Yes     | Yes   | Yes    | No      | Colours, units (px, em) |
| Dockerfile   | No      | No    | Yes    | No      | --                      |
| Makefile     | No      | No    | Yes    | No      | --                      |

*MSD string literals are unquoted rest-of-line values, used only inside `project {}` blocks.

The lesson is clear: include only the literal types your domain requires. Each additional literal type adds complexity to the lexer and cognitive load for the user. MSD needs integers for type sizes and strings for project metadata -- nothing more.

## 4.5 Symbols and Punctuation

Symbols and punctuation are the structural glue of a language. They delimit blocks, separate items, annotate types, and mark special attributes. Getting symbols right is largely a matter of choosing the right balance between familiarity and domain specificity.

### Single-Character Tokens

MSD uses seven single-character symbols:

| Symbol | Token Type | Meaning                                     |
|--------|-----------|---------------------------------------------|
| `{`    | LBRACE    | Opens a block (entity body, project body)   |
| `}`    | RBRACE    | Closes a block                              |
| `(`    | LPAREN    | Opens a group (cardinality, type size)      |
| `)`    | RPAREN    | Closes a group                              |
| `:`    | COLON     | Separates name from type, key from value    |
| `,`    | COMMA     | Separates items (cardinality min from max)  |
| `*`    | STAR      | Marks primary key attributes                |

Each symbol was chosen for its familiarity. Braces `{}` for blocks come from C, Java, JavaScript, and Go. Parentheses `()` for grouping are universal across mathematics and programming. The colon `:` for type annotation follows Python, TypeScript, and Pascal. The asterisk `*` for marking primary keys follows the convention used in database modelling diagrams, where primary key attributes are traditionally underlined or starred.

### Multi-Character Tokens

Many languages use multi-character symbols:

| Symbol | Languages      | Meaning                        |
|--------|---------------|--------------------------------|
| `//`   | C, Java, MSD  | Line comment                   |
| `->`   | C, Rust, PHP  | Arrow (dereference, return)    |
| `<=`   | Many          | Less than or equal             |
| `!=`   | Many          | Not equal                      |
| `::` | Rust, Haskell | Path separator, type annotation|
| `=>`   | JS, PHP       | Arrow function, array mapping  |
| `...`  | JS, Python    | Spread operator, ellipsis      |

MSD has only one multi-character token: `//` for line comments. This reflects the language's simplicity -- there are no operators, no comparisons, no arrows. MSD is a declarative data definition language, not a computational one.

### Choosing Symbols: Familiarity vs Domain Conventions

When selecting symbols, favour conventions that your target audience already knows. MSD's users are primarily computer science students and database practitioners who are familiar with C-family syntax. Using `{}`  for blocks and `:` for type annotations leverages their existing knowledge.

However, domain conventions can override programming conventions. MSD uses `*` for primary keys because this is how primary keys are conventionally marked in MERISE diagrams -- with an asterisk or underline. A programmer unfamiliar with MERISE might expect `*` to mean multiplication or pointer dereference, but MSD's target audience immediately recognises its meaning.

Here is a table of common symbols and their typical meanings across DSLs:

| Symbol | Database DSLs           | Programming Languages    | Configuration DSLs  |
|--------|------------------------|--------------------------|---------------------|
| `{}`   | Block delimiters       | Block delimiters         | Block delimiters    |
| `()`   | Parameter lists, sizes | Function calls, grouping | --                  |
| `:`    | Type annotation        | Type annotation, slice   | Key-value separator |
| `,`    | List separator         | List separator           | --                  |
| `;`    | Statement terminator   | Statement terminator     | --                  |
| `*`    | Primary key, wildcard  | Multiplication, pointer  | Glob wildcard       |
| `=`    | --                     | Assignment               | Value assignment    |

> **Warning:** Avoid reusing a symbol with two very different meanings in the same language. If `*` means "primary key" in one context and "wildcard" in another, users will be confused. MSD uses `*` exclusively for primary keys, avoiding ambiguity.

## 4.6 Whitespace and Indentation

How a language treats whitespace is one of the most visible and debated aspects of its design. There are two fundamental approaches.

### Insignificant Whitespace

In languages with **insignificant whitespace**, spaces, tabs, and blank lines serve only to separate tokens. The parser ignores them entirely. This means the following MSD fragments are all equivalent:

```
entity Student { *student_id: INT name: VARCHAR(100) }
```

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
}
```

```
entity    Student
{
    *student_id:    INT
    name:           VARCHAR(100)
}
```

C, Java, JavaScript, Go, SQL, and MSD all use insignificant whitespace. The advantage is flexibility: users can format their code however they prefer, and the language works the same regardless. Tools like auto-formatters can reformat code without changing its meaning.

### Significant Whitespace

In languages with **significant whitespace**, indentation carries structural meaning. Python is the most prominent example:

```python
def greet(name):
    if name:
        print(f"Hello, {name}")
    else:
        print("Hello, world")
```

Removing the indentation changes the program's meaning -- or more likely, causes a syntax error. YAML, Haskell (in its layout-sensitive mode), and Makefile (which requires tabs for recipe lines) also use significant whitespace.

### Comparing the Two Approaches

| Aspect              | Insignificant Whitespace    | Significant Whitespace      |
|---------------------|----------------------------|-----------------------------|
| Visual structure    | Optional (by convention)   | Mandatory (by grammar)      |
| Parser complexity   | Simpler                    | More complex (indent tracking)|
| Formatting freedom  | High                       | Constrained                 |
| Copy-paste safety   | Robust                     | Fragile (indentation lost)  |
| Delimiter characters| Needed (`{}`, `begin`/`end`) | Not needed                 |
| Readability         | Depends on discipline      | Enforced consistency        |

### The MSD Choice

MSD uses insignificant whitespace. Indentation is conventional -- the examples in this book indent block contents by four spaces -- but the lexer does not enforce it. This decision was made for several reasons:

1. **Simplicity**: The lexer does not need to track indentation levels or emit INDENT/DEDENT tokens.
2. **Robustness**: Users can copy-paste MSD fragments without worrying about indentation.
3. **Familiarity**: MSD's target audience (computer science students) is accustomed to brace-delimited blocks from C and Java.

That said, MSD's lexer does emit NEWLINE tokens. These are not strictly necessary for a language with insignificant whitespace, but they serve a practical purpose: they allow the parser to provide accurate line numbers in error messages and to handle the line-oriented nature of the `project {}` block, where each key-value pair occupies a single line.

## 4.7 Comments

Comments are text that the lexer recognises and discards. They carry no meaning in the language itself, but they are essential for users: comments explain intent, provide documentation, temporarily disable code, and annotate models with domain knowledge.

### Line Comments

A **line comment** starts with a special marker and extends to the end of the line. Different languages use different markers:

| Marker | Languages                        |
|--------|----------------------------------|
| `#`    | Python, Shell, Ruby, YAML, TOML, MSD |
| `//`   | C, C++, Java, JavaScript, Go, Rust, MSD |
| `--`   | SQL, Haskell, Lua, Ada          |
| `%`    | LaTeX, Erlang, Prolog           |

MSD supports **both** `#` and `//` line comments:

```
# This is a comment using the hash style
entity Student {
    *student_id: INT   // This is a comment using the double-slash style
    name: VARCHAR(100) # Both styles work
}
```

Why offer two styles? The reasoning is practical rather than theoretical. MSD is a data definition language used in educational contexts. Students coming from Python or Shell scripting instinctively reach for `#`. Students coming from C or Java instinctively reach for `//`. By accepting both, MSD meets users where they are, reducing friction and avoiding a class of "why doesn't my comment work?" errors.

The implementation is straightforward -- the lexer checks for both markers:

```python
# Comments: # or //
if ch == "#":
    break  # skip rest of line
if ch == "/" and col + 1 < length and line_text[col + 1] == "/":
    break  # skip rest of line
```

### Block Comments

**Block comments** start with one marker and end with another, potentially spanning multiple lines:

```c
/* This is a
   multi-line block comment
   in C */
```

```haskell
{- This is a
   multi-line block comment
   in Haskell -}
```

MSD does not support block comments. This is a deliberate omission: MSD files are typically short (tens of lines, not hundreds), and line comments suffice for all practical purposes. Block comments add complexity to the lexer (they require tracking nesting depth if you want to support nested block comments) without providing proportional value.

### Documentation Comments

Some languages provide a special comment syntax for documentation that can be extracted by tools:

```java
/**
 * Represents a student in the university system.
 * @param name The student's full name
 */
```

```rust
/// Represents a student in the university system.
///
/// # Examples
/// ...
```

MSD does not have a documentation comment syntax. However, since MSD files describe database schemas, the `project {}` block serves a similar purpose -- it provides structured metadata (name, author, version) that tools can extract and display. If a future version of MSD needed richer documentation, adding a `///` doc-comment syntax would be a natural extension.

## 4.8 Context-Sensitive Lexing

In most languages, the lexer is **context-free**: the same character sequence always produces the same token, regardless of where it appears. The character `{` is always LBRACE, the character `:` is always COLON, and the word `entity` is always the ENTITY keyword.

MSD mostly follows this rule, with one notable exception: **the colon token behaves differently inside `project {}` blocks**.

### The Problem

Consider these two MSD fragments:

```
project {
    name: University Database
}

entity Student {
    *student_id: INT
}
```

In the entity block, the colon separates an attribute name from its type: `student_id` COLON `INT`. The parser expects an IDENTIFIER token after the colon.

In the project block, the colon separates a metadata key from a free-form value: `name` COLON `University Database`. The value is not a single identifier -- it is an arbitrary string that may contain spaces, punctuation, and anything else.

If the lexer treated the colon the same way in both contexts, it would tokenise `University Database` as two separate IDENTIFIER tokens (`University` and `Database`), and the parser would need complex rules to reassemble them. A simpler approach is for the lexer to recognise the context.

### The Solution

MSD's lexer tracks whether it is currently inside a `project {}` block. When it encounters a colon inside such a block, it captures everything after the colon (up to a comment marker or end of line) as a single STRING_VALUE token:

```python
# Colon -- context-sensitive in project blocks
if ch == ":":
    tokens.append(Token(TokenType.COLON, ":", line_num, col + 1))
    col += 1

    if in_project_block:
        # Capture rest of line as STRING_VALUE
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

The `in_project_block` flag is set when the lexer encounters the `project` keyword and cleared when the matching `}` is reached.

### Keep Context Sensitivity Minimal

Context-sensitive lexing is powerful but dangerous. Each piece of context the lexer must track is a piece of state that can go wrong, and it makes the lexer harder to reason about. MSD has exactly one context-sensitive rule, and it is well-contained: the flag is set on one keyword and cleared on one brace.

> **Info:** Context-sensitive lexing is more common than you might think. JavaScript's template literals (`` `Hello, ${name}` ``) require the lexer to switch between "string mode" and "expression mode". Python's f-strings have similar complexity. Ruby's heredocs, Perl's regular expression literals, and XML's CDATA sections are all examples of context-sensitive lexing in production languages. The key is to use it sparingly and to keep the context-switching rules simple.

Other DSL designs might avoid context sensitivity entirely. Section 4.10 includes an exercise asking you to redesign MSD's project block without context-sensitive lexing -- for instance, by requiring quoted strings or a different block syntax.

## 4.9 Design Trade-Offs

Every lexical decision involves trade-offs. This section summarises the key tensions and how MSD navigates them.

### Familiarity vs Precision

Using symbols and conventions from well-known languages makes your DSL easier to learn. But familiar symbols can also mislead: if `*` means "pointer dereference" in C and "primary key" in MSD, a C programmer might be momentarily confused.

MSD leans toward familiarity for structural elements (`{}`, `()`, `:`) and uses domain-specific conventions only where the domain meaning is strong (`*` for primary keys). This hybrid approach works because MSD's target audience -- computer science students studying databases -- is familiar with both worlds.

### Brevity vs Readability

Short tokens are faster to type but harder to read. Consider these alternatives for marking a primary key:

| Syntax         | Style     | Example                     |
|---------------|-----------|-----------------------------|
| `*`            | Symbol    | `*student_id: INT`          |
| `@pk`          | Decorator | `@pk student_id: INT`       |
| `primary_key`  | Keyword   | `primary_key student_id: INT`|

MSD chose `*` because primary key marking is extremely common in MSD files (almost every entity has one), and a single character is the most concise option. The meaning is unambiguous because `*` has no other meaning in MSD. For a less frequently used feature, a more verbose syntax might be preferable.

### Consistency vs Convenience

A consistent language applies the same rules everywhere. A convenient language makes exceptions when they improve usability. MSD's context-sensitive colon is a convenience that breaks consistency -- the same character means different things in different contexts. The alternative (requiring quoted strings in project blocks) would be more consistent but less convenient for users.

### Summary of MSD's Lexical Choices

| Choice                    | MSD Decision                      | Rationale                                            |
|--------------------------|-----------------------------------|------------------------------------------------------|
| Number of keywords        | 4                                 | Minimal; one per domain concept                      |
| Keyword case sensitivity  | Case-insensitive                  | Accepts `entity`, `Entity`, `ENTITY`                 |
| Identifier case sensitivity| Case-sensitive                   | `Student` and `student` are different                |
| Identifier characters     | ASCII letters, digits, underscore | Simple; sufficient for database identifiers          |
| Block delimiters          | `{` `}`                           | Familiar to C/Java audience                          |
| Type annotation           | `:`                               | Familiar from Python/TypeScript                      |
| Primary key marker        | `*`                               | Concise; domain convention from MERISE diagrams      |
| Comment styles            | `#` and `//`                      | Dual support for Python and C-family users           |
| String literals           | Unquoted (project block only)     | Eliminates quoting errors; sufficient for metadata   |
| Whitespace                | Insignificant                     | Flexible formatting; simpler lexer                   |
| Context sensitivity       | Colon in project blocks only      | Minimal; enables unquoted string values              |

## 4.10 Exercises

**Exercise 4.1** -- *Keyword Design*

Design the keyword set for a DSL that describes cooking recipes. The language should express ingredients, quantities, preparation steps, cooking times, and temperatures. What keywords would you choose? How many do you need? Should keywords be case-sensitive? Write three example "programs" in your proposed syntax.

**Exercise 4.2** -- *Eliminating Context Sensitivity*

The MSD lexer uses context-sensitive behaviour for the colon token: inside `project {}` blocks, it triggers rest-of-line capture as a STRING_VALUE; outside, it is a simple separator. Propose an alternative design that avoids this context sensitivity entirely. Your design must still allow project metadata values that contain spaces (e.g., `University Database`). What trade-offs does your design introduce? Consider at least two alternatives (e.g., quoted strings, a different separator, a different block syntax).

**Exercise 4.3** -- *Symbol Overloading*

MSD uses parentheses `()` for two purposes: cardinalities in link statements (`(1,N)`) and type sizes in attribute declarations (`VARCHAR(100)`). Could these two uses ever be ambiguous? If so, design an alternative syntax for one of the uses that eliminates the ambiguity. If not, explain why the two uses can always be distinguished.

**Exercise 4.4** -- *Comment Style Survey*

Survey at least five DSLs or configuration formats you have used (e.g., SQL, CSS, JSON, YAML, TOML, Dockerfile, Makefile, .ini files). For each, document: (a) what comment syntax it supports, (b) whether it supports block comments, and (c) whether comments can appear anywhere or only in specific positions. What patterns do you observe?

**Exercise 4.5** -- *Significant Whitespace Redesign*

Redesign MSD's syntax to use significant whitespace (Python-style indentation) instead of braces. Write the lexical rules for your redesigned language, including how INDENT and DEDENT tokens would be generated. Rewrite the following MSD fragment in your new syntax:

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
    email: VARCHAR(255)
}

association Enrol {
    enrolment_date: DATE
}

link Student Enrol (1,N)
link Course Enrol (0,N)
```

What are the advantages and disadvantages of your redesign compared to the brace-based original?

**Exercise 4.6** -- *Unicode Identifiers*

MSD currently restricts identifiers to ASCII characters. Suppose you were internationalising MSD for use in universities worldwide, where entity names might include accented characters (e.g., `Etudiant`, `Universite`), Arabic script, or Chinese characters. What changes would you need to make to the lexer? What new problems would Unicode identifiers introduce for downstream stages (SQL generation, file I/O, display)? Would you allow all of Unicode, or restrict to specific categories (e.g., Unicode letters only)?

**Exercise 4.7** -- *Token Design for a Query DSL*

Design the complete token set (keywords, symbols, identifier rules, literal types, comment syntax) for a DSL that queries a music library. The language should support queries like "find all albums by Artist X released after 2010 with rating above 4 stars." List every token type, give examples of each, and justify your choices. Pay particular attention to how you handle string values that contain spaces (artist names, album titles).