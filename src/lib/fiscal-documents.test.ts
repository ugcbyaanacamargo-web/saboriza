import { describe, expect, it } from "vitest";
import { countByStatus, filterDocuments, isStuckProcessing, listProviders, NO_PROVIDER, toHttpLink, type FiscalDocumentRow } from "./fiscal-documents";

const NOW = new Date("2026-10-19T12:00:00Z");

function doc(partial: Partial<FiscalDocumentRow>): FiscalDocumentRow {
  return {
    id: "1", status: "AUTORIZADA", provider: "BASE", number: null, externalId: null, pdfRef: null, xmlRef: null,
    createdAt: "2026-10-19T10:00:00Z", updatedAt: "2026-10-19T10:00:00Z", ...partial,
  };
}

describe("countByStatus", () => {
  it("conta por status e ignora status desconhecido", () => {
    const counts = countByStatus([doc({}), doc({}), doc({ status: "REJEITADA" }), doc({ status: "XPTO" })]);
    expect(counts).toEqual({ NAO_EMITIDO: 0, PROCESSANDO: 0, AUTORIZADA: 2, REJEITADA: 1, CANCELADA: 0 });
  });
});

describe("isStuckProcessing", () => {
  it("detecta PROCESSANDO há mais de 24h", () => {
    expect(isStuckProcessing(doc({ status: "PROCESSANDO", updatedAt: "2026-10-18T11:00:00Z" }), NOW)).toBe(true);
  });
  it("não marca PROCESSANDO recente", () => {
    expect(isStuckProcessing(doc({ status: "PROCESSANDO", updatedAt: "2026-10-19T11:00:00Z" }), NOW)).toBe(false);
  });
  it("não marca outros status nem datas inválidas", () => {
    expect(isStuckProcessing(doc({ status: "AUTORIZADA", updatedAt: "2026-01-01T00:00:00Z" }), NOW)).toBe(false);
    expect(isStuckProcessing(doc({ status: "PROCESSANDO", updatedAt: "lixo", createdAt: "lixo" }), NOW)).toBe(false);
  });
});

describe("filterDocuments e listProviders", () => {
  const docs = [doc({ id: "a" }), doc({ id: "b", status: "REJEITADA", provider: "ASAAS" }), doc({ id: "c", provider: null })];
  it("filtra por status e provedor", () => {
    expect(filterDocuments(docs, "REJEITADA", null).map((d) => d.id)).toEqual(["b"]);
    expect(filterDocuments(docs, null, "BASE").map((d) => d.id)).toEqual(["a"]);
    expect(filterDocuments(docs, null, NO_PROVIDER).map((d) => d.id)).toEqual(["c"]);
    expect(filterDocuments(docs, null, null)).toHaveLength(3);
  });
  it("lista provedores únicos ordenados", () => {
    expect(listProviders(docs)).toEqual(["ASAAS", "BASE"]);
  });
});

describe("toHttpLink", () => {
  it("só aceita http(s)", () => {
    expect(toHttpLink("https://x.com/a.pdf")).toBe("https://x.com/a.pdf");
    expect(toHttpLink("javascript:alert(1)")).toBeNull();
    expect(toHttpLink("storage/path.pdf")).toBeNull();
    expect(toHttpLink(null)).toBeNull();
  });
});
