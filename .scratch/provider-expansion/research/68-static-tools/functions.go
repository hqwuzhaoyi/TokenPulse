// Read-only ELF metadata inspector for the pinned official artifact.
// This tool does not load or execute code from the inspected file.
package main

import (
	"crypto/sha256"
	"debug/elf"
	"debug/gosym"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

func main() {
	raw, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}
	if fmt.Sprintf("%x", sha256.Sum256(raw)) != "07d76becc367762e31f59ecbf744a967ce5ef1cbf395b4fc05835e6fb244a042" {
		panic("expected pinned official Central 1.11.0 Linux artifact")
	}
	f, e := elf.Open(os.Args[1])
	if e != nil {
		panic(e)
	}
	d, e := f.Section(".gopclntab").Data()
	if e != nil {
		panic(e)
	}
	t, e := gosym.NewTable(nil, gosym.NewLineTable(d, f.Section(".text").Addr))
	if e != nil {
		panic(e)
	}
	out := []map[string]any{}
	for _, fn := range t.Funcs {
		if strings.Contains(fn.Name, "central-cli/") || strings.Contains(fn.Name, "decimal.") || strings.Contains(fn.Name, "math/big") || strings.Contains(fn.Name, "net/http.NewRequest") || strings.Contains(fn.Name, "time.Unix") {
			file, line, _ := t.PCToLine(fn.Entry)
			out = append(out, map[string]any{"name": fn.Name, "start": fn.Entry, "end": fn.End, "file": file, "line": line})
		}
	}
	json.NewEncoder(os.Stdout).Encode(out)
}
