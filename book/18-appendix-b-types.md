\newpage

# Appendix B: MSD Data Type Reference

This appendix documents the 13 data types supported by MSD. Each type maps directly to a standard SQL data type.

## B.1 Type Summary

| Type | Category | Size Parameter | Description |
|------|----------|----------------|-------------|
| `INT` | Numeric | No | Standard integer (32-bit) |
| `BIGINT` | Numeric | No | Large integer (64-bit) |
| `SMALLINT` | Numeric | No | Small integer (16-bit) |
| `DECIMAL` | Numeric | Optional | Fixed-point decimal |
| `FLOAT` | Numeric | No | Single-precision floating point |
| `DOUBLE` | Numeric | No | Double-precision floating point |
| `VARCHAR` | String | Required | Variable-length character string |
| `CHAR` | String | Optional | Fixed-length character string |
| `TEXT` | String | No | Unlimited-length text |
| `BOOLEAN` | Logical | No | True/false value |
| `DATE` | Temporal | No | Calendar date (year, month, day) |
| `TIME` | Temporal | No | Time of day (hour, minute, second) |
| `TIMESTAMP` | Temporal | No | Date and time combined |

## B.2 Numeric Types

### INT

Standard 32-bit signed integer. Range: -2,147,483,648 to 2,147,483,647.

```
*id: INT
age: INT
quantity: INT
```

Use `INT` as the default integer type. It is the most common choice for primary keys, counters, and general-purpose integer fields.

### BIGINT

64-bit signed integer. Range: -9,223,372,036,854,775,808 to 9,223,372,036,854,775,807.

```
*id: BIGINT
population: BIGINT
```

Use `BIGINT` when values may exceed the `INT` range — for example, auto-incrementing primary keys in high-volume tables, or fields that store large counts.

### SMALLINT

16-bit signed integer. Range: -32,768 to 32,767.

```
rating: SMALLINT
priority: SMALLINT
```

Use `SMALLINT` for fields with a known small range. It saves storage compared to `INT` but offers limited range.

### DECIMAL

Fixed-point decimal number. Accepts an optional size parameter specifying precision.

```
price: DECIMAL
salary: DECIMAL(10)
```

Use `DECIMAL` for monetary values and any field where exact decimal representation matters. Floating-point types (`FLOAT`, `DOUBLE`) introduce rounding errors that are unacceptable for financial data.

### FLOAT

Single-precision (32-bit) IEEE 754 floating-point number. Approximately 7 significant decimal digits.

```
latitude: FLOAT
temperature: FLOAT
```

Use `FLOAT` for scientific measurements and approximate values where storage efficiency matters more than precision.

### DOUBLE

Double-precision (64-bit) IEEE 754 floating-point number. Approximately 15 significant decimal digits.

```
longitude: DOUBLE
distance: DOUBLE
```

Use `DOUBLE` when `FLOAT` does not provide sufficient precision. Prefer `DECIMAL` over `DOUBLE` for financial calculations.

## B.3 String Types

### VARCHAR

Variable-length character string. Requires a size parameter specifying the maximum length in characters.

```
name: VARCHAR(255)
email: VARCHAR(320)
code: VARCHAR(10)
```

`VARCHAR` is the most commonly used string type. Always specify a size — it documents the expected maximum length and enables database-level validation.

> **Tip:** Common sizes: `VARCHAR(255)` for general text fields, `VARCHAR(320)` for email addresses (per RFC 5321), `VARCHAR(50)` for short codes and abbreviations.

### CHAR

Fixed-length character string. Accepts an optional size parameter (defaults to 1 if omitted).

```
gender: CHAR(1)
country_code: CHAR(2)
currency: CHAR(3)
```

Use `CHAR` for fields with a known, fixed length — such as ISO country codes (`CHAR(2)`), currency codes (`CHAR(3)`), or single-character flags (`CHAR(1)`).

> **Note:** `CHAR` values are padded with spaces to the specified length. For variable-length data, prefer `VARCHAR`.

### TEXT

Unlimited-length text. No size parameter.

```
biography: TEXT
description: TEXT
notes: TEXT
```

Use `TEXT` for long-form content where no maximum length can reasonably be specified — such as descriptions, comments, or document bodies.

## B.4 Logical Types

### BOOLEAN

True/false value.

```
is_active: BOOLEAN
verified: BOOLEAN
published: BOOLEAN
```

Use `BOOLEAN` for binary flags and yes/no fields.

## B.5 Temporal Types

### DATE

Calendar date (year, month, day). No time component.

```
birth_date: DATE
hire_date: DATE
```

Use `DATE` for fields that represent calendar dates without a time-of-day component.

### TIME

Time of day (hour, minute, second). No date component.

```
opening_time: TIME
departure_time: TIME
```

Use `TIME` for fields that represent a time of day independently of any specific date.

### TIMESTAMP

Combined date and time, typically with timezone awareness.

```
created_at: TIMESTAMP
updated_at: TIMESTAMP
last_login: TIMESTAMP
```

Use `TIMESTAMP` for audit fields, event times, and any field that records when something happened.

> **Tip:** Prefer `TIMESTAMP` over separate `DATE` and `TIME` fields when both components are needed. It avoids the complexity of joining two fields and ensures atomic date-time values.

## B.6 Size Parameter Rules

Only three types accept a size parameter:

| Type | Size Parameter | Meaning | Example |
|------|---------------|---------|---------|
| `VARCHAR` | Required | Maximum character length | `VARCHAR(255)` |
| `CHAR` | Optional | Fixed character length (default 1) | `CHAR(3)` |
| `DECIMAL` | Optional | Precision (total digits) | `DECIMAL(10)` |

If a size parameter is specified on any other type, the parser emits a warning:

```
schema.msd:3: warning: size parameter ignored for type 'INT'
```

The warning is non-fatal — the model is still built, but the size value is discarded.

## B.7 Type Selection Guide

| Use Case | Recommended Type |
|----------|-----------------|
| Primary keys | `INT` or `BIGINT` |
| Short text (names, codes) | `VARCHAR(n)` |
| Long text (descriptions) | `TEXT` |
| Fixed-length codes | `CHAR(n)` |
| Money and prices | `DECIMAL` |
| Scientific measurements | `FLOAT` or `DOUBLE` |
| Yes/no flags | `BOOLEAN` |
| Calendar dates | `DATE` |
| Event timestamps | `TIMESTAMP` |
| Time-of-day values | `TIME` |
| Counters and quantities | `INT` |
| Small-range integers | `SMALLINT` |
| Large-range integers | `BIGINT` |
