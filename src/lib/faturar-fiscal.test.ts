import { describe, expect, it } from "vitest";
import { emissionFailureMessage, isProductNfeAvailable, resolveFiscalChoice, fiscalDocumentName, fiscalEmissionFunction, hasValidDocument, isEmitChoice, productNfePendencies } from "./faturar-fiscal";

const okProduct = { name: "Tempero A", ncm: "21039011", saleUnit: "CX" };
const okCustomer = { document: "11.222.333/0001-81", baseCustomerId: null };

describe("faturar-fiscal", () => {
  it("roteia cada escolha para a função de emissão correta", () => {
    expect(fiscalEmissionFunction("EMITIR_NFE")).toBe("asaas-emit-invoice");
    expect(fiscalEmissionFunction("EMITIR_NFE_PRODUTO")).toBe("base-create-invoice");
    expect(fiscalEmissionFunction("SEM_DOCUMENTO_FISCAL")).toBeNull();
  });

  it("identifica escolhas que emitem e seus rótulos", () => {
    expect(isEmitChoice("EMITIR_NFE_PRODUTO")).toBe(true);
    expect(isEmitChoice("SEM_DOCUMENTO_FISCAL")).toBe(false);
    expect(fiscalDocumentName("EMITIR_NFE")).toBe("NFS-e");
    expect(fiscalDocumentName("EMITIR_NFE_PRODUTO")).toBe("NF-e de produto");
  });

  it("valida CPF e CNPJ", () => {
    expect(hasValidDocument("11.222.333/0001-81")).toBe(true);
    expect(hasValidDocument("529.982.247-25")).toBe(true);
    expect(hasValidDocument("123")).toBe(false);
    expect(hasValidDocument(null)).toBe(false);
  });

  it("sem pendências quando tudo está cadastrado", () => {
    expect(productNfePendencies([okProduct], okCustomer)).toEqual([]);
  });

  it("lista NCM, unidade e documento ausentes", () => {
    const pend = productNfePendencies([{ name: "X", ncm: null, saleUnit: " " }], { document: null, baseCustomerId: null });
    expect(pend).toHaveLength(3);
  });

  it("aceita cliente sem documento se já tem cadastro no Base", () => {
    expect(productNfePendencies([okProduct], { document: null, baseCustomerId: "abc" })).toEqual([]);
  });

  it("pedido sem itens ou cliente ausente gera pendência", () => {
    expect(productNfePendencies([], null)).toHaveLength(2);
  });
});

describe("disponibilidade da NF-e de produto", () => {
  it("só libera com credencial BASE ativa", () => {
    expect(isProductNfeAvailable([])).toBe(false);
    expect(isProductNfeAvailable(null)).toBe(false);
    expect(isProductNfeAvailable([{ provider: "ASAAS", isActive: true }])).toBe(false);
    expect(isProductNfeAvailable([{ provider: "BASE", isActive: false }])).toBe(false);
    expect(isProductNfeAvailable([{ provider: "BASE", isActive: false }, { provider: "BASE", isActive: true }])).toBe(true);
  });

  it("força NFS-e quando NF-e de produto está indisponível", () => {
    expect(resolveFiscalChoice("EMITIR_NFE_PRODUTO", false)).toBe("EMITIR_NFE");
    expect(resolveFiscalChoice("EMITIR_NFE_PRODUTO", true)).toBe("EMITIR_NFE_PRODUTO");
    expect(resolveFiscalChoice("SEM_DOCUMENTO_FISCAL", false)).toBe("SEM_DOCUMENTO_FISCAL");
  });

  it("monta aviso de falha de emissão a partir de error ou data.error", () => {
    expect(emissionFailureMessage("EMITIR_NFE", null, {})).toBeNull();
    expect(emissionFailureMessage("EMITIR_NFE", { message: "boom" }, null)).toContain("NFS-e não foi emitida (boom)");
    expect(emissionFailureMessage("EMITIR_NFE_PRODUTO", null, { error: "sem credencial" })).toContain("NF-e de produto não foi emitida (sem credencial)");
    expect(emissionFailureMessage("EMITIR_NFE", null, { error: "x" })).toContain("NAO_EMITIDO");
  });
});
