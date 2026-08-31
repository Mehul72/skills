---
name: goimports
description: Go's official **code formatting + automatic import management tool**, an enhanced version of `gofmt`
allowed-tools:
    - Read
    - Write
    - Bash
version: 1.0.2
user-invocable: true
---

# Overview
`goimports` is Go's official **code formatting + automatic import management tool**, an enhanced version of `gofmt`.
Core capabilities:
- Automatically **add missing** import packages
- Automatically **remove unused** import packages
- Automatically group and sort imports (stdlib / third-party / local packages)
- Maintain code style fully compliant with Go official standards


# Installation

```bash
go install golang.org/x/tools/cmd/goimports@latest
```

Verify:
```bash
goimports -version
```
---

# Common Commands

## 1. Format a Single File (overwrite in place)
```bash
goimports -w main.go
```

## 2. Format Entire Project (recursively all .go files)
```bash
goimports -w ./...
```

## 3. Only Show Which Files Need Formatting (no modification)
```bash
goimports -l ./...
```

## 4. View Before/After Formatting Diff
```bash
goimports -d main.go
```

## 5. Format Only, Without Modifying Imports (equivalent to gofmt)
```bash
goimports -format-only -w main.go
```

# Advanced Parameters

| Parameter | Purpose |
|------|------|
| `-w` | Write result back to original file (required) |
| `-l` | List files that don't conform to format |
| `-d` | Show diff comparison |
| `-e` | Show full syntax errors |
| `-local` | Specify local package prefix for separate grouping |
| `-format-only` | Format only, don't manage imports |
| `-srcdir` | Specify source root directory for import lookup |


# Local Package Grouping (Enterprise Standard)
Group project internal packages separately for clearer formatting:

```bash
goimports -local "your.company/project" -w ./...
```

Result:
```go
import (
    // stdlib
    "context"
    "fmt"

    // third-party
    "github.com/gin-gonic/gin"

    // local project (separate group)
    "your.company/project/pkg/util"
)
```

# Typical Use Cases

## How to automatically clean up unused imports?
→ Use `goimports -w file.go` or `goimports -w ./...`

## How to automatically import missing packages?
→ `goimports` automatically completes imports based on code identifiers.

### How to make imports automatically grouped and sorted?
→ `goimports -local your-project-prefix -w ./...`

### Format but don't want to change imports?
→ `goimports -format-only -w main.go`


# Errors and Common Issues

## 1. command not found: goimports
Cause: `$GOPATH/bin` not in PATH, or Go toolchain not in PATH
Solution: Ensure Go toolchain is available in PATH:
```bash
goimports -w ./...
```

## 2. Local packages not grouped correctly
Solution: Must use `-local` to specify project prefix.

## 3. Imports cannot be auto-recognized (internal packages / private repos)
Solution: Use `-srcdir` to specify source root directory.
