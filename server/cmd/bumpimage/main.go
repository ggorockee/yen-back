// Command bumpimage sets a scalar in a Helm values file by dotted key path,
// keeping comments and key order. CI uses it to update the image tag in the
// infra repo (GitOps), replacing the Python update_values.py used elsewhere.
//
//	go run ./cmd/bumpimage -file infra/charts/helm/prod/yen-back/values.yaml -key image.tag -value 20261115-abc1234
//
// Exit status: 0 changed, 0 with "unchanged" on stdout when already set, 1 on error.
package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

func main() {
	file := flag.String("file", "", "values.yaml path")
	key := flag.String("key", "image.tag", "dotted key path, e.g. server.image.tag")
	value := flag.String("value", "", "new value")
	flag.Parse()

	if *file == "" || *value == "" {
		fmt.Fprintln(os.Stderr, "usage: bumpimage -file values.yaml -key image.tag -value TAG")
		os.Exit(1)
	}
	changed, err := bumpFile(*file, *key, *value)
	if err != nil {
		fmt.Fprintln(os.Stderr, "bumpimage:", err)
		os.Exit(1)
	}
	if changed {
		fmt.Printf("updated %s: %s = %s\n", *file, *key, *value)
	} else {
		fmt.Println("unchanged")
	}
}

func bumpFile(path, key, value string) (bool, error) {
	in, err := os.ReadFile(path)
	if err != nil {
		return false, err
	}
	out, changed, err := bump(in, key, value)
	if err != nil || !changed {
		return false, err
	}
	return true, os.WriteFile(path, out, 0o644)
}

// bump sets key to value (as a quoted string) in the YAML document.
// Missing intermediate mappings are created.
func bump(in []byte, key, value string) ([]byte, bool, error) {
	var doc yaml.Node
	if err := yaml.Unmarshal(in, &doc); err != nil {
		return nil, false, fmt.Errorf("parse: %w", err)
	}
	if doc.Kind == 0 {
		doc = yaml.Node{Kind: yaml.DocumentNode, Content: []*yaml.Node{{Kind: yaml.MappingNode}}}
	}
	if doc.Kind != yaml.DocumentNode || len(doc.Content) != 1 || doc.Content[0].Kind != yaml.MappingNode {
		return nil, false, errors.New("top level must be a mapping")
	}

	node := doc.Content[0]
	parts := strings.Split(key, ".")
	for i, part := range parts {
		if part == "" {
			return nil, false, fmt.Errorf("invalid key %q", key)
		}
		child := lookup(node, part)
		last := i == len(parts)-1
		if child == nil {
			kind := yaml.MappingNode
			if last {
				kind = yaml.ScalarNode
			}
			child = &yaml.Node{Kind: kind}
			node.Content = append(node.Content, &yaml.Node{Kind: yaml.ScalarNode, Value: part}, child)
		}
		if last {
			if child.Kind != yaml.ScalarNode {
				return nil, false, fmt.Errorf("%s is not a scalar", key)
			}
			if child.Value == value {
				return in, false, nil
			}
			child.Value, child.Tag, child.Style = value, "!!str", yaml.DoubleQuotedStyle
			break
		}
		if child.Kind != yaml.MappingNode {
			return nil, false, fmt.Errorf("%s is not a mapping", strings.Join(parts[:i+1], "."))
		}
		node = child
	}

	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err := enc.Encode(&doc); err != nil {
		return nil, false, err
	}
	return buf.Bytes(), true, enc.Close()
}

func lookup(m *yaml.Node, key string) *yaml.Node {
	for i := 0; i+1 < len(m.Content); i += 2 {
		if m.Content[i].Value == key {
			return m.Content[i+1]
		}
	}
	return nil
}
