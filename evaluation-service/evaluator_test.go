package main

import "testing"

func TestGetDeterministicBucket_RangeAndDeterminism(t *testing.T) {
	inputs := []string{"user123new-checkout", "abc", "", "outro-usuario-outra-flag"}

	for _, in := range inputs {
		b1 := getDeterministicBucket(in)
		b2 := getDeterministicBucket(in)

		if b1 != b2 {
			t.Fatalf("getDeterministicBucket(%q) não é determinístico: %d != %d", in, b1, b2)
		}
		if b1 < 0 || b1 > 99 {
			t.Fatalf("getDeterministicBucket(%q) = %d, esperado um valor entre 0 e 99", in, b1)
		}
	}
}

func TestGetDeterministicBucket_SameUserSameFlagAlwaysSameResult(t *testing.T) {
	// Garante a propriedade central do bucket determinístico descrita na
	// arquitetura: o mesmo usuário sempre cai no mesmo bucket para a mesma flag.
	key := "user123" + "new-checkout"
	first := getDeterministicBucket(key)
	for i := 0; i < 10; i++ {
		if got := getDeterministicBucket(key); got != first {
			t.Fatalf("bucket mudou entre chamadas: %d != %d", first, got)
		}
	}
}
