import { create } from "zustand";
import { supabase } from "@/lib/supabase";
import { criarReceita, estornarRecebimento, newCommandId, receberReceita } from "@/lib/financeiro-rpcs";
import { resolveCurrentCompanyId } from "@/lib/current-company";

export type RevenueOrigin = "MANUAL" | "CONTRATO_RECORRENCIA" | "INTEGRACAO" | "OUTRO_MODULO";
export type ReceivableStatus = "ABERTO" | "RECEBIDO" | "VENCIDO" | "CANCELADO";

export interface Revenue {
  id: string;
  receivableId: string;
  description: string;
  category: string;
  origin: RevenueOrigin;
  amount: number;
  openBalance: number;
  installmentNumber: number;
  totalInstallments: number;
  payerId: string | null;
  payerName: string | null;
  dueDate: string | null;
  status: ReceivableStatus;
  receivedAt: string | null;
}

export interface Receipt {
  id: string;
  receivableId: string;
  receivedAmount: number;
  effectiveDate: string;
  reversedReceiptId: string | null;
}

export interface NewRevenueInput {
  description: string;
  category: string;
  origin: RevenueOrigin;
  amount: number;
  dueDate?: string;
  payerOriginId?: string;
  installments?: number;
}

interface ReceitasState {
  revenues: Revenue[];
  receipts: Receipt[];
  status: "idle" | "loading" | "ready" | "error";

  fetchAll: () => Promise<void>;
  createRevenue: (input: NewRevenueInput) => Promise<string | null>;
  markReceived: (receivableId: string, receivedAmount: number) => Promise<string | null>;
  reverseReceipt: (receiptId: string) => Promise<string | null>;
}

export const useReceitasStore = create<ReceitasState>((set, get) => ({
  revenues: [],
  receipts: [],
  status: "idle",

  fetchAll: async () => {
    set({ status: "loading" });

    const companyId = await resolveCurrentCompanyId();
    if (!companyId) {
      set({ status: "error" });
      return;
    }

    const [{ data: rows, error }, { data: receiptRows }] = await Promise.all([
      supabase
        .from("revenue_receivables")
        .select(
          "id, due_date, effective_date, status, principal, open_balance, installment_number, total_installments, revenue_id, revenues(id, description, category, origin, payer_origin_id, customers(name))"
        )
        .eq("company_id", companyId)
        .order("due_date", { ascending: false }),
      supabase
        .from("revenue_receipts")
        .select("id, receivable_id, received_amount, effective_date, reversed_receipt_id")
        .eq("company_id", companyId),
    ]);

    if (error) {
      set({ status: "error" });
      return;
    }

    set({
      revenues: (rows ?? []).map((r) => {
        const revenue = r.revenues as unknown as {
          id: string;
          description: string;
          category: string;
          origin: RevenueOrigin;
          payer_origin_id: string | null;
          customers: { name: string } | null;
        } | null;
        return {
          id: revenue?.id ?? r.revenue_id,
          receivableId: r.id,
          description: revenue?.description ?? "-----",
          category: revenue?.category ?? "-----",
          origin: revenue?.origin ?? "MANUAL",
          amount: r.principal,
          openBalance: r.open_balance,
          installmentNumber: r.installment_number,
          totalInstallments: r.total_installments,
          payerId: revenue?.payer_origin_id ?? null,
          payerName: revenue?.customers?.name ?? null,
          dueDate: r.due_date,
          status: r.status as ReceivableStatus,
          receivedAt: r.effective_date,
        };
      }),
      receipts: (receiptRows ?? []).map((r) => ({
        id: r.id,
        receivableId: r.receivable_id,
        receivedAmount: r.received_amount,
        effectiveDate: r.effective_date,
        reversedReceiptId: r.reversed_receipt_id,
      })),
      status: "ready",
    });
  },

  createRevenue: async (input) => {
    const { error } = await criarReceita(newCommandId(), {
      description: input.description,
      category: input.category,
      origin: input.origin,
      amount: input.amount,
      dueDate: input.dueDate || null,
      payerOriginId: input.payerOriginId || null,
      installments: input.installments ?? 1,
    });
    if (error) return error;

    await get().fetchAll();
    return null;
  },

  markReceived: async (receivableId, receivedAmount) => {
    const { error } = await receberReceita(newCommandId(), receivableId, receivedAmount);
    if (error) return error;

    await get().fetchAll();
    return null;
  },

  reverseReceipt: async (receiptId) => {
    const { error } = await estornarRecebimento(newCommandId(), receiptId);
    if (error) return error;

    await get().fetchAll();
    return null;
  },
}));
