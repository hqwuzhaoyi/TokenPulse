// Read-only ELF metadata inspector for the pinned official artifact.
// This tool does not load or execute code from the inspected file.
package main

import (
	"crypto/sha256"
	"debug/elf"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

var f *elf.File
var cache = map[*elf.Section][]byte{}

func read(a, n uint64) []byte {
	for _, s := range f.Sections {
		if a >= s.Addr && a+n <= s.Addr+s.Size {
			d, ok := cache[s]
			if !ok {
				var e error
				d, e = s.Data()
				if e != nil {
					panic(e)
				}
				cache[s] = d
			}
			return d[a-s.Addr : a-s.Addr+n]
		}
	}
	panic("bad address")
}
func u64(a uint64) uint64 { return binary.LittleEndian.Uint64(read(a, 8)) }
func u32(a uint64) uint32 { return binary.LittleEndian.Uint32(read(a, 4)) }
func name(a uint64) (string, string) {
	flags := read(a, 1)[0]
	p := a + 1
	len, n := binary.Uvarint(read(p, 10))
	p += uint64(n)
	text := string(read(p, len))
	p += len
	tag := ""
	if flags&2 != 0 {
		len, n = binary.Uvarint(read(p, 10))
		p += uint64(n)
		tag = string(read(p, len))
	}
	return text, tag
}
func typename(a uint64) string {
	offset := int32(u32(a + 40))
	n, _ := name(uint64(int64(f.Section(".rodata").Addr) + int64(offset)))
	if read(a+20, 1)[0]&2 != 0 {
		n = strings.TrimPrefix(n, "*")
	}
	return n
}
func main() {
	raw, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}
	if fmt.Sprintf("%x", sha256.Sum256(raw)) != "07d76becc367762e31f59ecbf744a967ce5ef1cbf395b4fc05835e6fb244a042" {
		panic("expected pinned official Central 1.11.0 Linux artifact")
	}
	var e error
	f, e = elf.Open(os.Args[1])
	if e != nil {
		panic(e)
	}
	d, _ := f.Section(".typelink").Data()
	base := f.Section(".rodata").Addr
	out := []map[string]any{}
	seen := map[uint64]bool{}
	for p := 0; p+4 <= len(d); p += 4 {
		a := uint64(int64(base) + int64(int32(binary.LittleEndian.Uint32(d[p:]))))
		n := typename(a)
		if !strings.Contains(n, "oauth.") && !strings.Contains(n, "tokenResponse") && !strings.Contains(n, "struct { Token ") {
			continue
		}
		if read(a+23, 1)[0]&31 == 22 {
			a = u64(a + 48)
		}
		if seen[a] {
			continue
		}
		seen[a] = true
		n = typename(a)
		row := map[string]any{"name": n, "address": a, "kind": read(a+23, 1)[0] & 31}
		if read(a+23, 1)[0]&31 == 25 {
			ptr := u64(a + 56)
			count := u64(a + 64)
			fields := []map[string]any{}
			for i := uint64(0); i < count; i++ {
				q := ptr + i*24
				nm, tag := name(u64(q))
				fields = append(fields, map[string]any{"name": nm, "tag": tag, "type": typename(u64(q + 8)), "offset": u64(q + 16)})
			}
			row["fields"] = fields
		}
		out = append(out, row)
	}
	json.NewEncoder(os.Stdout).Encode(out)
}
