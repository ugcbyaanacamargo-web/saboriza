import { describe, expect, it, vi } from "vitest";

vi.mock("@/lib/supabase", () => ({ supabase: { rpc: vi.fn() } }));

import { getBillingCreditState, getCreditUsage, parseCreditLimitInput } from "./customer-credit";

describe("getCreditUsage", () => {
  it("calcula a proporção usada e limita a barra em 100% mostrando o excesso", () => {
    expect(getCreditUsage({ credit_limit: 1000, current_exposure: 250, current_excess: 0 })).toEqual({ usedPercent: 25, barPercent: 25, excess: 0 });
    expect(getCreditUsage({ credit_limit: 1000, current_exposure: 1200, current_excess: 200 })).toEqual({ usedPercent: 120, barPercent: 100, excess: 200 });
  });

  it("sem limite aprovado não inventa percentual", () => {
    expect(getCreditUsage({ credit_limit: 0, current_exposure: 0 })).toEqual({ usedPercent: null, barPercent: 0, excess: 0 });
    expect(getCreditUsage({ credit_limit: 0, current_exposure: 80 }).excess).toBe(80);
  });
});

describe("parseCreditLimitInput", () => {
  it("aceita ponto decimal vindo do valor atual e vírgula/milhar digitados", () => {
    expect(parseCreditLimitInput("1000.5")).toBe(1000.5);
    expect(parseCreditLimitInput("1.500,25")).toBe(1500.25);
    expect(parseCreditLimitInput("0")).toBe(0);
  });

  it("recusa vazio, negativo e texto", () => {
    expect(parseCreditLimitInput("")).toBeNull();
    expect(parseCreditLimitInput("-1")).toBeNull();
    expect(parseCreditLimitInput("abc")).toBeNull();
  });
});

describe("getBillingCreditState", () => {
  const base = { overdue_amount: 40, available_after: -100, financed_part: 0, uncovered: [] as ("OVERDUE" | "OVER_LIMIT")[] | undefined };

  it("venda à vista (parte a prazo 0) nunca aparece como bloqueada por crédito", () => {
    expect(getBillingCreditState({ ...base, uncovered: undefined })).toEqual({ hasOverdue: false, overLimit: false, creditOk: true });
    expect(getBillingCreditState({ ...base, uncovered: [] }).creditOk).toBe(true);
  });

  it("parte a prazo com vencido ou acima do limite exige liberação", () => {
    expect(getBillingCreditState({ ...base, financed_part: 50, uncovered: undefined })).toEqual({ hasOverdue: true, overLimit: true, creditOk: false });
    expect(getBillingCreditState({ ...base, financed_part: 50, uncovered: ["OVERDUE"] }).creditOk).toBe(false);
  });

  it("exceção vigente cobre a parte a prazo e sem snapshot não libera", () => {
    expect(getBillingCreditState({ ...base, financed_part: 50, uncovered: [] }).creditOk).toBe(true);
    expect(getBillingCreditState(null).creditOk).toBe(false);
  });
});
