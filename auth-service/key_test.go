package main

import "testing"

func TestHashAPIKey_Deterministic(t *testing.T) {
	h1 := hashAPIKey("tm_key_abc123")
	h2 := hashAPIKey("tm_key_abc123")
	if h1 != h2 {
		t.Fatalf("hashAPIKey não é determinístico: %s != %s", h1, h2)
	}
	if len(h1) != 64 {
		t.Fatalf("hashAPIKey deveria retornar 64 caracteres hex (SHA-256), retornou %d", len(h1))
	}
}

func TestHashAPIKey_DifferentInputsDifferentHashes(t *testing.T) {
	h1 := hashAPIKey("key-one")
	h2 := hashAPIKey("key-two")
	if h1 == h2 {
		t.Fatalf("esperava hashes diferentes para chaves diferentes")
	}
}

func TestGenerateAPIKey_HasPrefixAndIsUnique(t *testing.T) {
	k1, err := generateAPIKey()
	if err != nil {
		t.Fatalf("generateAPIKey retornou erro: %v", err)
	}
	if len(k1) < len("tm_key_") || k1[:7] != "tm_key_" {
		t.Fatalf("chave gerada sem o prefixo tm_key_: %q", k1)
	}

	k2, err := generateAPIKey()
	if err != nil {
		t.Fatalf("generateAPIKey retornou erro: %v", err)
	}
	if k1 == k2 {
		t.Fatalf("esperava que duas chamadas gerassem chaves diferentes")
	}
}
