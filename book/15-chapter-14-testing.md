\newpage

# Chapter 14: Testing DSL Implementations

A DSL implementation without tests is a liability. The input space of a language — even a small one — is vast, and the interactions between lexer, parser, and semantic analyser create subtle edge cases. This chapter describes the testing strategy for DSL implementations, using MSD's 64-test suite as the model.

## 14.1 Testing Philosophy

MSD's test suite follows three principles:

### Test Each Layer Independently

The lexer tests do not depend on the parser. The parser tests do not depend on the builder. Each layer is tested with its own inputs and expected outputs:

```python
# Lexer test — directly calls tokenize()
def test_all_keywords(self, lexer):
    tokens, errors = lexer.tokenize("project entity association link")
    types = _types(tokens)
    assert types == [TokenType.PROJECT, TokenType.ENTITY,
                     TokenType.ASSOCIATION, TokenType.LINK]

# Parser test — directly calls parse()
def test_single_entity(self, parser):
    result = parser.parse("entity Foo {\n    *id: INT\n}")
    assert not result.has_errors
    assert len(result.entities) == 1

# Builder test — parses then builds
def test_builds_project(self, parser, builder):
    result = parser.parse(SIMPLE_MSD)
    project, errors = builder.build(result)
    assert project is not None
```

Independent testing isolates bugs: if a builder test fails, you know the bug is in the builder, not the parser.

### Test Both Success and Failure Paths

For every feature, there are tests for correct input *and* tests for invalid input:

```python
# Success: valid cardinalities
def test_all_cardinalities(self, parser):
    for card in ["(0,1)", "(0,N)", "(1,1)", "(1,N)"]:
        source = f"entity E {{ *id: INT }}\nassociation A {{ }}\nlink E {card} A"
        result = parser.parse(source)
        assert not result.has_errors

# Failure: invalid cardinality
def test_invalid_cardinality_min(self, parser):
    result = parser.parse("entity E { *id: INT }\nassociation A { }\nlink E (5,N) A")
    assert result.has_errors
    assert any("invalid minimum cardinality" in e.message for e in result.errors)
```

> **Tip:** Aim for at least one positive test and one negative test per language feature. The negative tests often catch more bugs than the positive ones, because error paths are where implementations tend to be weakest.

### Test the Contract, Not the Implementation

Tests verify observable behaviour, not internal state:

```python
# Good: tests the output
def test_entities_get_positions(self, parser, builder):
    result = parser.parse(SIMPLE_MSD)
    project, _ = builder.build(result)
    positions = [(e.x, e.y) for e in project.get_all_entities()]
    assert not all(x == 0 and y == 0 for x, y in positions)

# Bad: tests internal state
# assert layout._temperature == 0.1  # implementation detail
```

If you test the contract, you can refactor the implementation freely. If you test internals, every refactoring breaks tests.

## 14.2 Lexer Tests

### Token Extraction Helpers

Lexer tests use helper functions to filter out structural tokens:

```python
def _types(tokens):
    """Extract non-NEWLINE, non-EOF token types."""
    return [t.type for t in tokens
            if t.type not in (TokenType.NEWLINE, TokenType.EOF)]

def _values(tokens):
    """Extract non-NEWLINE, non-EOF token values."""
    return [t.value for t in tokens
            if t.type not in (TokenType.NEWLINE, TokenType.EOF)]
```

These helpers let tests focus on meaningful tokens without noise from structural tokens.

### What to Test: Lexer

| Category | Examples |
|----------|----------|
| Empty input | Empty string, whitespace only |
| Comments | Hash, double-slash, inline after code |
| Keywords | All four keywords, case insensitivity |
| Symbols | All seven symbol tokens |
| Identifiers | Regular identifiers, underscores, digits |
| Integers | Single-digit, multi-digit |
| Project values | STRING_VALUE capture, comment stripping |
| Positions | Correct line numbers, correct columns |
| Invalid characters | Single error, multiple errors, recovery |
| Full constructs | Entity block, link statement |

### Notable Test: Context-Sensitive Project Values

```python
def test_project_string_value_with_comment(self, lexer):
    source = "project {\n    name: My Project # a comment\n}"
    tokens, errors = lexer.tokenize(source)
    string_vals = [t.value for t in tokens if t.type == TokenType.STRING_VALUE]
    assert string_vals == ["My Project"]
```

This verifies that comments are stripped from project values — a subtle behaviour of the context-sensitive lexer that would be easy to break accidentally.

## 14.3 Parser Tests

### What to Test: Parser

| Category | Examples |
|----------|----------|
| Minimal constructs | Single entity, empty entity, single link |
| Composite PKs | Multiple `*` attributes |
| Sized types | VARCHAR(n), DECIMAL(n), CHAR(n) |
| Size warnings | Size on unsized type (INT(10)) |
| Associations | Empty body, with carrying attributes |
| Links | All four cardinalities |
| Metadata | Project block present, absent, unknown property |
| Full file | Complete MSD with all constructs |
| Errors | Missing brace, invalid type, invalid cardinality |
| Multi-error | Multiple errors found, recovery after error |

### Notable Test: Error Recovery

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
```

This test exercises attribute-level panic-mode recovery. Entity A's invalid attribute triggers recovery, but Entity B is still parsed successfully.

> **Note:** Error recovery tests are among the most valuable in a DSL test suite. They verify that a single mistake does not cascade into a flood of false errors, which is the most common complaint users have about compilers and linters.

### Notable Test: All Cardinalities

```python
def test_all_cardinalities(self, parser):
    for min_val, max_val in [("0", "1"), ("0", "N"), ("1", "1"), ("1", "N")]:
        source = f"""entity E {{ *id: INT }}
association A {{ }}
link E ({min_val},{max_val}) A"""
        result = parser.parse(source)
        assert not result.has_errors
        assert len(result.links) == 1
        link = result.links[0]
        assert link.cardinality_min == min_val
        assert link.cardinality_max == max_val
```

Parameterised tests cover all valid combinations concisely.

## 14.4 Semantic Tests (Builder Tests)

### What to Test: Semantics

| Category | Examples |
|----------|----------|
| Simple build | Project creation, attribute mapping |
| UUIDs | Uniqueness, link reference validity |
| Metadata | Applied correctly, defaults when absent |
| Duplicate errors | Duplicate entity, duplicate association |
| Name conflicts | Association name matching entity name |
| Unknown references | Unknown entity in link, unknown association |
| Suggestions | "Did you mean?" for entity, for association |
| Warnings | Entity without primary key |
| Auto-layout | Positions assigned, no all-zero positions |
| Round-trip | Save to .merisio, reload, verify |

### Notable Test: "Did You Mean?"

```python
def test_suggestion_for_entity(self, parser, builder):
    source = """entity Tourist { *id: INT }
association R { }
link Tourits (0,N) R"""
    result = parser.parse(source)
    project, errors = builder.build(result)
    fatal = [e for e in errors if e.severity == "error"]
    assert any("did you mean 'Tourist'" in e.message for e in fatal)
```

This verifies the complete suggestion pipeline: Levenshtein distance is computed between "Tourits" and "Tourist" (distance 2, within threshold 3), and the suggestion appears in the error message.

### Notable Test: Round-Trip

```python
def test_save_and_load(self, parser, builder, tmp_path):
    from src.utils.file_io import FileIO

    result = parser.parse(FULL_MSD)
    project, errors = builder.build(result)
    assert not any(e.severity == "error" for e in errors)

    file_path = str(tmp_path / "test.merisio")
    assert FileIO.save_project(project, file_path) is True

    loaded = FileIO.load_project(file_path)
    assert loaded is not None
    assert len(loaded.get_all_entities()) == len(project.get_all_entities())
    assert loaded.name == "Tourism System"
```

This test verifies the complete pipeline: MSD text $\rightarrow$ parse $\rightarrow$ build $\rightarrow$ save as JSON $\rightarrow$ reload $\rightarrow$ verify. It uses pytest's `tmp_path` fixture for a clean temporary directory.

## 14.5 Integration Tests

Integration tests exercise the complete pipeline end-to-end, verifying that all stages work together correctly.

### The Full Pipeline Test

```python
def test_full_pipeline(self, tmp_path):
    parser = MSDParser()
    builder = MSDProjectBuilder()

    result = parser.parse(COMPLETE_MSD, filename="test.msd")
    assert not result.has_errors

    project, errors = builder.build(result)
    fatal = [e for e in errors if e.severity == "error"]
    assert len(fatal) == 0

    # Verify project structure
    assert project.name == "Tourism Management System"
    entities = project.get_all_entities()
    entity_names = {e.name for e in entities}
    assert entity_names == {"Tourist", "Role", "Guide", "Experience"}

    # Save and reload
    file_path = str(tmp_path / "output.merisio")
    assert FileIO.save_project(project, file_path) is True

    loaded = FileIO.load_project(file_path)
    assert loaded is not None

    # Verify JSON structure
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert len(data["mcd"]["entities"]) == 4
```

### Other Integration Tests

| Test | What it verifies |
|------|-----------------|
| Line numbers | Error messages include correct line numbers |
| Comments | Comments do not affect parsing |
| Case-insensitive keywords | `ENTITY`, `Entity`, `entity` all work |
| Case-sensitive identifiers | `Foo` and `foo` are different entities |

## 14.6 Test Fixtures and Shared Test Data

### Constant MSD Strings

Builder and integration tests share MSD strings defined at module level:

```python
SIMPLE_MSD = """entity Tourist {
    *id: INT
    name: VARCHAR(255)
}
association voyager { }
link Tourist (1,N) voyager
"""

FULL_MSD = """project {
    name: Tourism System
    author: Test Author
    description: A test project
}
entity Tourist {
    *id: INT
    name: VARCHAR(255)
    email: VARCHAR(255)
}
entity Guide {
    *id: INT
    name: VARCHAR(200)
}
association accompagner {
    date_debut: DATE
}
link Tourist (0,N) accompagner
link Guide (1,N) accompagner
"""
```

### Pytest Fixtures

```python
@pytest.fixture
def lexer():
    return MSDLexer()

@pytest.fixture
def parser():
    return MSDParser()

@pytest.fixture
def builder():
    return MSDProjectBuilder()
```

Each test gets a fresh instance, ensuring no state leaks between tests.

> **Info:** MSD's 64 tests run in approximately 0.06 seconds. Fast tests encourage running them frequently — after every change, not just before committing. If your test suite takes minutes, developers will skip it.

## 14.7 MSD: Walkthrough of the 64-Test Suite

### Organisation

| File | Tests | Focus |
|------|-------|-------|
| `test_msd_lexer.py` | 18 | Tokenisation, comments, keywords, context sensitivity |
| `test_msd_parser.py` | 22 | All constructs, error cases, multi-error recovery |
| `test_msd_builder.py` | 19 | Project building, validation, suggestions, round-trip |
| `test_msd_integration.py` | 5 | End-to-end pipeline, JSON verification |

### Coverage Strategy

Every token type has at least one test. Every parse rule has at least one test. Every error type has at least one test. Every validation rule has at least one test. This systematic coverage ensures that changes to any part of the pipeline will be caught by at least one test.

### Running the Tests

```bash
# Run all MSD tests
python -m pytest tests/test_msd_*.py -v

# Run a specific file
python -m pytest tests/test_msd_lexer.py -v

# Run a specific test class
python -m pytest tests/test_msd_parser.py::TestErrorCases -v

# Run with coverage
python -m pytest tests/test_msd_*.py --cov=src/msd
```

## 14.8 Exercises

**Exercise 14.1.** Write three lexer tests for edge cases: empty input, input with only comments, and input with only whitespace. What should the token stream contain in each case?

**Exercise 14.2.** Write a parser test that verifies error recovery works across three consecutive entities, where the middle one has an invalid type. Verify that the first and third entities are parsed correctly.

**Exercise 14.3.** Design a test for a new semantic rule: "every association must be connected by at least two links." Write both the validation code in the builder and the test.

**Exercise 14.4.** MSD has 64 tests for approximately 600 lines of implementation code — roughly one test per 10 lines. Is this ratio appropriate? Compare with other projects you have worked on. What is the relationship between test count and code confidence?

**Exercise 14.5.** The round-trip test verifies parse $\rightarrow$ build $\rightarrow$ save $\rightarrow$ load. Design a **reverse round-trip** test: load a .merisio file, generate MSD text from it, parse the text, and verify the result matches the original. What additional code would you need to implement?

**Exercise 14.6.** Write a property-based test (using Hypothesis or a similar library) that generates random valid MSD files and verifies that they parse without errors. What generators would you need?

**Exercise 14.7.** MSD's tests use constant MSD strings at module level. An alternative is to store test fixtures as separate .msd files. Compare the two approaches. When would file-based fixtures be preferable?
