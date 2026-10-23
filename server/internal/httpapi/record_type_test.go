package httpapi

import "testing"

func TestValidRecordTypeAcceptsGrowth(t *testing.T) {
	if !validRecordType("growth") {
		t.Fatal("growth should be a valid record type")
	}
	if validRecordType("unknown-type") {
		t.Fatal("unknown record types must stay rejected")
	}
}
