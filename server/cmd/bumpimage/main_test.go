package main

import (
	"strings"
	"testing"
)

const values = `# yen-back values
replicaCount: 1
image:
  repository: ggorockee/yen-back-server
  # pinned by CI
  tag: "20261101-aaaaaaa"
  pullPolicy: IfNotPresent
`

func TestBumpKeepsCommentsAndOrder(t *testing.T) {
	out, changed, err := bump([]byte(values), "image.tag", "20261115-bbbbbbb")
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	s := string(out)
	for _, want := range []string{"# yen-back values", "# pinned by CI", `tag: "20261115-bbbbbbb"`, "pullPolicy: IfNotPresent"} {
		if !strings.Contains(s, want) {
			t.Errorf("output missing %q:\n%s", want, s)
		}
	}
	if strings.Index(s, "repository") > strings.Index(s, "tag:") {
		t.Error("key order changed")
	}
}

func TestBumpUnchanged(t *testing.T) {
	_, changed, err := bump([]byte(values), "image.tag", "20261101-aaaaaaa")
	if err != nil || changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
}

func TestBumpCreatesMissingPath(t *testing.T) {
	out, changed, err := bump([]byte("replicaCount: 1\n"), "server.image.tag", "x")
	if err != nil || !changed {
		t.Fatal(err)
	}
	if !strings.Contains(string(out), "server:\n  image:\n    tag: \"x\"") {
		t.Errorf("got:\n%s", out)
	}
}

func TestBumpRejectsNonScalar(t *testing.T) {
	if _, _, err := bump([]byte(values), "image", "x"); err == nil {
		t.Fatal("expected error when target is a mapping")
	}
	if _, _, err := bump([]byte(values), "replicaCount.x", "x"); err == nil {
		t.Fatal("expected error when walking through a scalar")
	}
}
