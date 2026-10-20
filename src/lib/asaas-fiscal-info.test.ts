import { describe, expect, it } from "vitest";
import { interpretFiscalInfo } from "../../supabase/functions/asaas-fiscal-info/interpret";

const fiscalOk = { municipalInscription: "123", cnae: "5611201", serviceListItem: "17.01", certificateSent: true };
const municipalCert = { authenticationType: "CERTIFICATE", usesServiceListItem: true };

describe("asaas-fiscal-info · interpretação do cadastro fiscal", () => {
  it("cadastro completo é configurado", () => {
    const r = interpretFiscalInfo({ status: 200, body: fiscalOk }, { status: 200, body: municipalCert });
    expect(r).toEqual({ kind: "OK", summary: { configured: true, missing: [], municipal_checked: true } });
  });

  it("404 significa sem informações fiscais", () => {
    const r = interpretFiscalInfo({ status: 404, body: {} }, null);
    expect(r).toEqual({ kind: "OK", summary: { configured: false, missing: ["informacoes_fiscais"], municipal_checked: false } });
  });

  it("aponta inscrição municipal e CNAE vazios", () => {
    const r = interpretFiscalInfo({ status: 200, body: { municipalInscription: " ", cnae: null } }, null);
    expect(r.kind === "OK" && r.summary.missing).toEqual(["inscricao_municipal", "cnae"]);
    expect(r.kind === "OK" && r.summary.municipal_checked).toBe(false);
  });

  it("exige item da lista e certificado quando o município pede", () => {
    const r = interpretFiscalInfo({ status: 200, body: { municipalInscription: "1", cnae: "1" } }, { status: 200, body: municipalCert });
    expect(r.kind === "OK" && r.summary.missing).toEqual(["item_lista_servicos", "certificado_digital"]);
  });

  it("autenticação por token e por usuário/senha", () => {
    const base = { municipalInscription: "1", cnae: "1" };
    const token = interpretFiscalInfo({ status: 200, body: base }, { status: 200, body: { authenticationType: "TOKEN" } });
    const user = interpretFiscalInfo({ status: 200, body: { ...base, username: "u" } }, { status: 200, body: { authenticationType: "USER_AND_PASSWORD" } });
    expect(token.kind === "OK" && token.summary.missing).toEqual(["token_acesso"]);
    expect(user.kind === "OK" && user.summary.missing).toEqual(["usuario_senha"]);
  });

  it("falha nas opções municipais não derruba a leitura", () => {
    const r = interpretFiscalInfo({ status: 200, body: fiscalOk }, { status: 500, body: {} });
    expect(r.kind === "OK" && r.summary).toEqual({ configured: true, missing: [], municipal_checked: false });
  });

  it("401 vira erro de credencial e 500 vira erro de conexão, sem expor corpo", () => {
    expect(interpretFiscalInfo({ status: 401, body: { errors: [{ description: "segredo" }] } }, null).kind).toBe("CREDENTIAL");
    const r = interpretFiscalInfo({ status: 500, body: "stack" }, null);
    expect(r.kind).toBe("CONNECTION");
    expect(JSON.stringify(r)).not.toContain("stack");
  });

  it("resposta mal formada não quebra e não vaza valores", () => {
    const r = interpretFiscalInfo({ status: 200, body: "texto" }, null);
    expect(r.kind === "OK" && r.summary.configured).toBe(false);
    const full = interpretFiscalInfo({ status: 200, body: { ...fiscalOk, email: "a@b.com", username: "joao" } }, { status: 200, body: municipalCert });
    expect(JSON.stringify(full)).not.toContain("a@b.com");
  });
});
