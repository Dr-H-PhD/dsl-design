\newpage

# Chapter 15: Tool Integration

A DSL without tool integration is an academic exercise. The language pipeline — lexer, parser, builder — is a library. To be useful, it must be accessible through the interfaces that users actually work with: command-line tools for automation and scripting, graphical interfaces for visual exploration, and documentation for discoverability. This chapter covers the patterns for integrating a DSL into real-world tooling.

## 15.1 CLI Integration

### Subcommands and Argument Parsing

A DSL CLI typically offers multiple subcommands — one per major operation:

```bash
merisio-cli schema.msd parse [-o output.merisio]
merisio-cli schema.merisio validate
merisio-cli schema.merisio sql -o schema.sql
merisio-cli schema.merisio mld
merisio-cli schema.merisio export --format png -o diagram.png
```

The `parse` subcommand accepts `.msd` files; the others accept `.merisio` files. The file is a positional argument; subcommand-specific options use flags.

### Exit Codes

Exit codes communicate success or failure to shell scripts and CI systems:

| Exit Code | Meaning | Example |
|-----------|---------|---------|
| 0 | Success | File parsed and saved |
| 1 | Validation/parse errors | Unknown type, duplicate name |
| 2 | Runtime error | File not found, write failure |

> **Tip:** Always use distinct exit codes for different failure modes. A CI pipeline that treats all non-zero codes identically cannot distinguish between "the model has errors" (fixable by the author) and "the tool crashed" (needs infrastructure attention).

### Error Output

Errors go to stderr; success messages go to stdout. This lets users pipe output cleanly:

```bash
# Errors appear on terminal; output goes to file
merisio-cli schema.msd parse > /dev/null
```

### Implementation: The `cmd_parse` Function

```python
def cmd_parse(args):
    from src.msd import MSDParser, MSDProjectBuilder
    from src.utils.file_io import FileIO

    file_path = args.file
    if not os.path.isfile(file_path):
        print(f"Error: file not found: {file_path}", file=sys.stderr)
        sys.exit(2)

    try:
        with open(file_path, "r", encoding="utf-8") as f:
            source = f.read()
    except OSError as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        sys.exit(2)

    parser = MSDParser()
    parse_result = parser.parse(source, filename=file_path)

    builder = MSDProjectBuilder()
    project, errors = builder.build(parse_result)

    has_fatal = False
    for err in errors:
        print(str(err), file=sys.stderr)
        if err.severity == "error":
            has_fatal = True

    if has_fatal:
        print("Parse failed with errors.", file=sys.stderr)
        sys.exit(1)

    output = args.output
    if not output:
        base, _ = os.path.splitext(file_path)
        output = base + ".merisio"

    if FileIO.save_project(project, output):
        print(f"Saved project to {output}")
    else:
        print(f"Error: failed to save project to {output}", file=sys.stderr)
        sys.exit(2)
```

Key design choices:

- **Lazy imports**: `MSDParser` and `MSDProjectBuilder` are imported inside the function, not at module level. This avoids loading MSD modules when the user runs unrelated commands like `info` or `sql`.

- **Default output path**: if `-o` is not specified, the output file is the input filename with a `.merisio` extension (`school.msd` $\rightarrow$ `school.merisio`).

- **All errors printed**: even when there are fatal errors, all warnings are also shown so the user sees everything.

## 15.2 GUI Integration

### The Import Workflow

GUI integration adds a menu item that triggers the DSL pipeline:

1. **File > Import MSD...** — placed after "Open..." in the File menu
2. A file dialog opens, filtered to `.msd` files
3. The file is read and processed through the MSD pipeline
4. Errors are presented in modal dialogs
5. On success, the model appears on the canvas with auto-layout

### Error Presentation

The GUI adapts error presentation to the graphical context:

| Situation | Behaviour |
|-----------|-----------|
| Fatal errors | `QMessageBox.critical` — import blocked, all errors listed |
| Warnings only | `QMessageBox.warning` — import proceeds, warnings listed |
| No errors | Silent import, status bar message |

```python
if fatal_errors:
    msg = "Import failed with errors:\n\n"
    msg += "\n".join(f"- {e}" for e in fatal_errors)
    if warnings:
        msg += "\n\nWarnings:\n"
        msg += "\n".join(f"- {e}" for e in warnings)
    QMessageBox.critical(self, "Import Error", msg)
    return

if warnings:
    msg = "Import succeeded with warnings:\n\n"
    msg += "\n".join(f"- {e}" for e in warnings)
    QMessageBox.warning(self, "Import Warnings", msg)
```

### Post-Import Actions

After a successful import, the GUI must update all views:

```python
self._project = project
self._dictionary_view.set_project(self._project)
self._mcd_canvas.set_project(self._project)
self._mcd_canvas.apply_colors(self._project.colors)
self._mld_view.set_project(self._project)
self._sql_view.set_project(self._project)
self._update_title()
self._update_status(f"Imported MSD: {file_path}")
self._mcd_canvas.zoom_fit()
```

The `zoom_fit()` call is essential: auto-layout positions may be far from the default viewport, so without it the user would see an empty canvas.

> **Note:** The GUI and CLI follow exactly the same pipeline. The only differences are input source (file dialog vs command-line argument), error presentation (message boxes vs stderr), and success action (canvas update vs file save). This consistency is a direct result of building the DSL core as a library.

## 15.3 Man Pages and Documentation

### Unix Convention

CLI tools on Unix should provide man pages. MSD's `merisio-cli(1)` man page documents all subcommands:

```
.SS parse
Parse an MSD (Merisio Schema Definition) file and convert it to a
\&.merisio project.
.PP
.RS
.B merisio-cli
.I file.msd
.B parse
.RB [ \-o
.IR output ]
.RE
```

### Essential Documentation

At minimum, a DSL tool should provide:

- `--help` flag on every command and subcommand
- `--version` flag for the main binary
- Man page (Unix) or help file (Windows) for detailed reference
- Error message catalogue (implicitly, through good error messages)

### Documentation as a First-Class Deliverable

Documentation should be treated as part of the implementation, not an afterthought. When adding a new subcommand:

1. Implement the command
2. Add tests
3. Update the man page
4. Update `--help` text

If documentation is always updated alongside code, it stays accurate.

## 15.4 Batch Processing and CI Pipelines

One of the primary motivations for creating a text-based DSL is enabling automation. Text files can be version-controlled, diffed, reviewed, and processed in bulk.

### Batch Conversion

```bash
# Convert all .msd files in a directory
for f in models/*.msd; do
    merisio-cli "$f" parse -o "output/$(basename "${f%.msd}.merisio")"
done
```

### CI Pipeline

```bash
# Parse, validate, and generate SQL in a CI pipeline
merisio-cli schema.msd parse -o /tmp/schema.merisio
merisio-cli /tmp/schema.merisio validate
merisio-cli /tmp/schema.merisio sql -o schema.sql
```

### Version Control Workflows

MSD files are plain text, which enables:

- **Clean diffs**: adding an attribute is a one-line diff, not a binary blob change

- **Code review**: reviewers can read and comment on model changes in pull requests

- **CI validation**: automated parsing catches errors before merge
- **Blame**: `git blame` shows who added each entity and when

> **Info:** This is perhaps the strongest argument for text-based DSLs. A graphical-only tool cannot participate in the code review workflow that modern software teams depend on. A text DSL turns domain models into reviewable, versionable artefacts.

## 15.5 The Integration Pattern: Library $\rightarrow$ CLI Wrapper $\rightarrow$ GUI Wrapper

The most robust integration architecture has three layers:

```
┌─────────────────────────────┐
│         DSL Library          │
│  (lexer, parser, builder)    │
└──────────┬──────────────────┘
           │
     ┌─────┴─────┐
     │           │
┌────┴────┐ ┌───┴─────┐
│   CLI   │ │   GUI   │
│ Wrapper │ │ Wrapper │
└─────────┘ └─────────┘
```

**The library** is the core: importable modules with no I/O dependencies. It reads strings, returns objects and error lists.

**The CLI wrapper** is a thin adapter: reads files from disk, calls the library, formats output for the terminal, sets exit codes.

**The GUI wrapper** is another thin adapter: opens file dialogs, calls the library, shows message boxes, updates the canvas.

Both wrappers call the same pipeline:

```
Read source → MSDParser().parse() → MSDProjectBuilder().build() → Handle errors → Use project
```

The library does not know about files, terminals, or windows. This separation provides:

- **Testability**: test the library directly with string input, no I/O needed

- **Reusability**: new wrappers (web API, language server, IDE plugin) are trivial to build

- **Consistency**: every wrapper uses the same pipeline, so behaviour is identical

## 15.6 MSD: The `parse` Command and File > Import MSD

A side-by-side comparison shows the pattern clearly:

| Aspect | CLI | GUI |
|--------|-----|-----|
| Input source | `args.file` (command line) | `QFileDialog.getOpenFileName()` |
| Read file | `open(file_path, "r")` | `open(file_path, "r")` |
| Parse | `MSDParser().parse(source, filename)` | `MSDParser().parse(source, filename)` |
| Build | `MSDProjectBuilder().build(result)` | `MSDProjectBuilder().build(result)` |
| Error output | `print(err, file=sys.stderr)` | `QMessageBox.critical()` |
| Warning output | `print(err, file=sys.stderr)` | `QMessageBox.warning()` |
| Success action | `FileIO.save_project()` | `self._mcd_canvas.set_project()` |
| Post-action | `sys.exit(0)` | `self._mcd_canvas.zoom_fit()` |

The parse and build lines are identical. Only the input and output handling differs.

## 15.7 Exercises

**Exercise 15.1.** Design a CLI for a hypothetical recipe DSL. What subcommands would you offer? (`parse`, `validate`, `nutrition`, `convert-to-metric`?) What exit codes would you define? What arguments would each subcommand accept?

**Exercise 15.2.** Add a `--strict` flag to the MSD CLI that treats warnings as errors. Write the implementation. Should `--strict` change the severity in error objects, or should it change how the error list is evaluated?

**Exercise 15.3.** Design a VS Code extension for MSD files. What features would you provide? (Syntax highlighting, error squiggles, hover information, auto-complete, go-to-definition?) Which features require just the lexer, which require the parser, and which require the builder?

**Exercise 15.4.** MSD uses lazy imports in `cmd_parse()`. Measure the import time of the MSD modules. Is lazy importing worthwhile? At what point does a module become expensive enough to justify lazy loading?

**Exercise 15.5.** Extend the integration pattern to include a **language server** (LSP). What would the language server wrapper look like? How would it differ from the CLI and GUI wrappers? What library features would it need that the current wrappers do not?

**Exercise 15.6.** Design a web-based import tool for MSD: a web page where users paste MSD text and see a rendered diagram. What components from the existing pipeline can you reuse? What new components are needed?
