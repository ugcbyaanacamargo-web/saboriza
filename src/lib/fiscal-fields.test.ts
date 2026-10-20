import { describe, expect, it } from "vitest";
import { isValidCnae, isValidMunicipalRegistration, validateFiscalFields } from "./fiscal-fields";

describe("campos fiscais", () => {
  it("CNAE exige 7 dígitos numéricos", () => {
    expect(isValidCnae("1091101")).toBe(true);
    expect(isValidCnae("109110")).toBe(false);
    expect(isValidCnae("10911012")).toBe(false);
    expect(isValidCnae("10911a1")).toBe(false);
  });

  it("inscrição municipal é opcional e alfanumérica", () => {
    expect(isValidMunicipalRegistration("")).toBe(true);
    expect(isValidMunicipalRegistration("12.345-6/A")).toBe(true);
    expect(isValidMunicipalRegistration("12 345")).toBe(false);
    expect(isValidMunicipalRegistration("a".repeat(21))).toBe(false);
  });

  it("validateFiscalFields devolve a primeira mensagem de erro ou null", () => {
    const ok = { cnaeCode: "", municipalRegistration: "", municipalServiceCode: "" };
    expect(validateFiscalFields(ok)).toBeNull();
    expect(validateFiscalFields({ ...ok, cnaeCode: "12" })).toMatch(/CNAE/);
    expect(validateFiscalFields({ ...ok, municipalRegistration: "!!" })).toMatch(/Inscrição municipal/);
    expect(validateFiscalFields({ ...ok, municipalServiceCode: "x".repeat(21) })).toMatch(/serviço/);
  });
});
