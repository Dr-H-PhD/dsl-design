\newpage

# Appendix C: DSL Design Checklist

This appendix provides a step-by-step checklist for designing and implementing a new domain-specific language from scratch. Each phase builds on the previous one. The chapter references point to where each topic is covered in detail.

## Phase 1: Domain Analysis (Chapter 3)

- [ ] Identify the target domain and its boundaries
- [ ] List the core domain concepts (nouns: entities, objects, resources)
- [ ] List the core domain operations (verbs: create, link, transform, validate)
- [ ] List the relationships between concepts (one-to-one, one-to-many, many-to-many)
- [ ] List the constraints that the domain imposes (uniqueness, cardinality, type restrictions)
- [ ] Identify the target users — who will write in this language?
- [ ] Identify the target tools — what will consume the language output?
- [ ] Study existing solutions — what tools do users currently use?
- [ ] Document what works and what is painful about current solutions
- [ ] Define the scope — what is explicitly *not* part of the language?

> **Tip:** Scope is the most important decision. A DSL that tries to do everything becomes a poor general-purpose language. Define what is out of scope before designing what is in scope.

## Phase 2: Lexical Design (Chapter 4)

- [ ] Choose keywords — one per major concept, short and familiar
- [ ] Decide on case sensitivity (keywords, identifiers, or both)
- [ ] Choose identifier rules — what characters are allowed in names?
- [ ] Choose literal types — strings, integers, floats, booleans?
- [ ] Choose symbol tokens — braces, parentheses, colons, commas, special markers
- [ ] Choose comment syntax — line comments, block comments, or both?
- [ ] Decide on whitespace significance — is indentation meaningful?
- [ ] Decide on line significance — are newlines meaningful?
- [ ] Identify any context-sensitive lexing needs
- [ ] Verify that no keyword conflicts with likely user identifiers
- [ ] Write down the complete token type list

> **Warning:** Avoid choosing keywords that are common domain terms. If users frequently need to name things "type" or "name", do not make those keywords.

## Phase 3: Syntactic Design (Chapter 5)

- [ ] Write the grammar in EBNF notation
- [ ] Verify the grammar is unambiguous — every valid input has exactly one parse tree
- [ ] Verify the grammar is LL(1) — each rule can be determined by one token of lookahead
- [ ] Choose the top-level structure — file as a sequence of declarations?
- [ ] Choose the block structure — braces, indentation, or keywords (begin/end)?
- [ ] Choose delimiter style — commas, semicolons, newlines, or nothing?
- [ ] Decide on optional elements — what can be omitted?
- [ ] Decide on ordering constraints — must declarations appear in a specific order?
- [ ] Write at least three example files covering simple, typical, and complex cases
- [ ] Read the example files aloud — do they sound natural?
- [ ] Show the example files to a potential user — can they guess the meaning?

## Phase 4: Semantic Design (Chapter 6)

- [ ] Define the type system — what types exist? Are they parameterised?
- [ ] Define name binding rules — where are names declared? Where are they referenced?
- [ ] Define scoping rules — are names global or local?
- [ ] Define uniqueness constraints — what names must be unique?
- [ ] Define reference resolution — how are forward references handled?
- [ ] Define validation rules — what constraints beyond syntax must be checked?
- [ ] Classify each validation rule as error (fatal) or warning (informational)
- [ ] Design error messages for each validation rule — specific, actionable, with context
- [ ] Consider "did you mean?" suggestions for name resolution failures
- [ ] Document the complete semantic specification

## Phase 5: Implementation (Chapters 8–12)

### Lexer (Chapter 8)

- [ ] Define the `Token` data structure (type, value, line, column)
- [ ] Implement the tokeniser — line-by-line or character-by-character
- [ ] Handle keyword recognition (identifier-to-keyword mapping)
- [ ] Handle comments (strip or skip)
- [ ] Handle whitespace and newlines
- [ ] Handle context-sensitive tokens (if any)
- [ ] Report lexical errors with line and column numbers
- [ ] Test: empty input, whitespace only, comments only
- [ ] Test: every keyword, every symbol, every literal type
- [ ] Test: invalid characters (recovery, not crash)

### Parser (Chapter 9)

- [ ] Choose the parsing technique — recursive descent for LL(1) grammars
- [ ] Define the intermediate representation (parse result, not final output)
- [ ] Implement one function per grammar rule
- [ ] Implement token navigation helpers (peek, advance, expect, skip)
- [ ] Implement panic-mode error recovery with synchronisation points
- [ ] Accumulate errors from the lexer and add parser errors
- [ ] Test: every grammar rule with valid input
- [ ] Test: every error case (missing tokens, invalid values)
- [ ] Test: error recovery — valid constructs after errors are still parsed

### Semantic Analyser / Builder (Chapter 10)

- [ ] Implement name registration and duplicate detection
- [ ] Implement reference resolution with error reporting
- [ ] Implement "did you mean?" suggestions (Levenshtein distance)
- [ ] Implement type validation
- [ ] Implement all semantic constraints
- [ ] Separate errors from warnings
- [ ] Accumulate errors from the parser and add builder errors
- [ ] Test: every validation rule (both success and failure)
- [ ] Test: duplicate names, unknown references, type errors
- [ ] Test: suggestion accuracy for common typos

### Output Generation (Chapter 11)

- [ ] Define the output format (JSON, XML, SQL, code, etc.)
- [ ] Implement the transformation from intermediate representation to output
- [ ] Generate stable identifiers (UUIDs) for persistent references
- [ ] Apply metadata and defaults
- [ ] Test: round-trip fidelity (parse → build → save → load → verify)

### Layout (Chapter 12, if applicable)

- [ ] Choose a layout algorithm appropriate to the domain
- [ ] Implement deterministic layout (fixed random seed)
- [ ] Implement post-processing (overlap removal, centering, rounding)
- [ ] Test: positions are assigned, no overlaps, deterministic results

## Phase 6: Integration (Chapters 13–15)

### Error Handling (Chapter 13)

- [ ] Use structured error objects, not exceptions, for user-facing errors
- [ ] Include location (file, line, column) in every error
- [ ] Use compiler-style error format (`file:line: severity: message`)
- [ ] Implement multi-error reporting — never stop at the first error
- [ ] Review every error message for specificity, actionability, and context

### Testing (Chapter 14)

- [ ] Test each layer independently (lexer, parser, builder)
- [ ] Test both success and failure paths for every feature
- [ ] Test the contract (observable behaviour), not the implementation
- [ ] Write integration tests that exercise the complete pipeline
- [ ] Aim for at least one positive and one negative test per language feature
- [ ] Ensure tests run fast (seconds, not minutes)

### Tool Integration (Chapter 15)

- [ ] Build the core as a library with no I/O dependencies
- [ ] Build a CLI wrapper — subcommands, exit codes, stderr for errors
- [ ] Build a GUI wrapper (if needed) — file dialogs, message boxes
- [ ] Provide `--help` and `--version` flags
- [ ] Write man pages or help documentation
- [ ] Test batch processing and CI pipeline usage

## Summary

| Phase | Key Deliverable |
|-------|----------------|
| 1. Domain Analysis | Scope document, concept list, constraint list |
| 2. Lexical Design | Token type list, keyword list |
| 3. Syntactic Design | EBNF grammar, example files |
| 4. Semantic Design | Validation rules, error message catalogue |
| 5. Implementation | Working lexer, parser, builder, output generator |
| 6. Integration | CLI tool, test suite, documentation |
