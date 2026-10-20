import { describe, expect, it } from "vitest";
import { httpFor } from "../../supabase/functions/asaas-webhook/outcome";

describe("asaas-webhook · tradução do resultado do banco para HTTP", () => {
  it("evento aplicado responde 200", () => {
    expect(httpFor({ ok: true, duplicate: false }, false)).toEqual({ status: 200, body: { ok: true } });
  });

  it("evento repetido responde 200 marcando duplicate", () => {
    expect(httpFor({ ok: true, duplicate: true }, false)).toEqual({ status: 200, body: { ok: true, duplicate: true } });
  });

  it("token inválido responde 401", () => {
    expect(httpFor({ ok: false, error: "TOKEN_INVALIDO" }, false).status).toBe(401);
  });

  it("falha de aplicação (retry) responde 500 para o Asaas reenviar", () => {
    expect(httpFor({ ok: false, error: "FALHA_APLICACAO", retry: true }, false).status).toBe(500);
  });

  it("erro na chamada da RPC ou resposta vazia responde 500", () => {
    expect(httpFor(null, true).status).toBe(500);
    expect(httpFor(null, false).status).toBe(500);
  });

  it("evento inválido ou de outra empresa responde 400 sem reenvio", () => {
    expect(httpFor({ ok: false, error: "EVENTO_INVALIDO" }, false)).toEqual({ status: 400, body: { error: "EVENTO_INVALIDO" } });
    expect(httpFor({ ok: false, error: "EVENTO_DE_OUTRA_EMPRESA" }, false).status).toBe(400);
  });
});
