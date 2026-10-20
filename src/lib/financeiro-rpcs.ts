import { supabase } from "@/lib/supabase";

export interface FinanceiroRpcResult<T> {
  data: T | null;
  error: string | null;
  replayed: boolean;
}

export interface PagarDespesaResult {
  expense_id: string;
  status: string;
  paid_amount: number;
  balance: number;
}

export interface ReceberReceitaResult {
  receipt_id: string;
  receivable_id: string;
  status: string;
  open_balance: number;
}

export interface EstornoRecebimentoResult {
  reversal_id: string;
  receivable_id: string;
  status: string;
  open_balance: number;
}

export interface RegistrarAporteInput {
  partnerId: string;
  amount: number;
  status: "PLANEJADO" | "REALIZADO";
  origin: string;
  plannedDate?: string | null;
  realizedDate?: string | null;
  notes?: string | null;
  expenseId?: string | null;
}

export interface RegistrarAporteResult {
  contribution_id: string;
  status: string;
}

export interface EstornoAporteResult {
  reversal_id: string;
  contribution_id: string;
}

export function newCommandId(): string {
  return crypto.randomUUID();
}

export function financeiroErrorMessage(message: string): string {
  if (message.startsWith("ESTORNO_JA_REALIZADO")) return "Este lançamento já foi estornado.";
  if (message.startsWith("COMANDO_REUSADO")) return "Esta operação já foi enviada com outros dados. Recarregue e tente de novo.";
  return message;
}

async function call<T>(fn: string, args: Record<string, unknown>): Promise<FinanceiroRpcResult<T>> {
  const { data, error } = await supabase.rpc(fn as never, args as never);
  if (error) return { data: null, error: financeiroErrorMessage(error.message), replayed: false };
  const body = (data ?? {}) as unknown as Record<string, unknown> & { replayed?: boolean };
  const { replayed, ...rest } = body;
  return { data: rest as unknown as T, error: null, replayed: replayed === true };
}

export function pagarDespesa(commandId: string, expenseId: string, amount: number) {
  return call<PagarDespesaResult>("financeiro_pagar_despesa", {
    p_command_id: commandId,
    p_expense_id: expenseId,
    p_amount: amount,
  });
}

export function receberReceita(commandId: string, receivableId: string, amount: number, effectiveDate?: string | null) {
  return call<ReceberReceitaResult>("financeiro_receber_receita", {
    p_command_id: commandId,
    p_receivable_id: receivableId,
    p_amount: amount,
    p_effective_date: effectiveDate ?? null,
  });
}

export function estornarRecebimento(commandId: string, receiptId: string, reason?: string | null) {
  return call<EstornoRecebimentoResult>("financeiro_estornar_recebimento", {
    p_command_id: commandId,
    p_receipt_id: receiptId,
    p_reason: reason ?? null,
  });
}

export function registrarAporte(commandId: string, input: RegistrarAporteInput) {
  return call<RegistrarAporteResult>("financeiro_registrar_aporte", {
    p_command_id: commandId,
    p_partner_id: input.partnerId,
    p_amount: input.amount,
    p_status: input.status,
    p_origin: input.origin,
    p_planned_date: input.plannedDate ?? null,
    p_realized_date: input.realizedDate ?? null,
    p_notes: input.notes ?? null,
    p_expense_id: input.expenseId ?? null,
  });
}

export function estornarAporte(commandId: string, contributionId: string, reason: string) {
  return call<EstornoAporteResult>("financeiro_estornar_aporte", {
    p_command_id: commandId,
    p_contribution_id: contributionId,
    p_reason: reason,
  });
}

export interface RealizarAporteResult {
  contribution_id: string;
  status: string;
  expense_paid: boolean;
}

export function realizarAporte(commandId: string, contributionId: string, realizedDate?: string | null) {
  return call<RealizarAporteResult>("financeiro_realizar_aporte", {
    p_command_id: commandId,
    p_contribution_id: contributionId,
    p_realized_date: realizedDate ?? null,
  });
}

export function cancelarAporte(commandId: string, contributionId: string, reason: string) {
  return call<{ contribution_id: string; status: string }>("financeiro_cancelar_aporte", {
    p_command_id: commandId,
    p_contribution_id: contributionId,
    p_reason: reason,
  });
}

export interface CriarReceitaInput {
  description: string;
  category: string;
  origin: string;
  amount: number;
  dueDate?: string | null;
  payerOriginId?: string | null;
  installments?: number | null;
}

export function criarReceita(commandId: string, input: CriarReceitaInput) {
  return call<{ revenue_id: string; installments: number }>("financeiro_criar_receita", {
    p_command_id: commandId,
    p_description: input.description,
    p_category: input.category,
    p_origin: input.origin,
    p_amount: input.amount,
    p_due_date: input.dueDate ?? null,
    p_payer_origin_id: input.payerOriginId ?? null,
    p_installments: input.installments ?? 1,
  });
}

export function solicitarAdiantamento(commandId: string, obligationId: string, amount: number) {
  return call<{ advance_id: string; status: string }>("financeiro_solicitar_adiantamento", {
    p_command_id: commandId,
    p_obligation_id: obligationId,
    p_amount: amount,
  });
}

export function baixarAtivo(commandId: string, assetUnitId: string, reason: string) {
  return call<{ asset_unit_id: string; movement_id: string; status: string }>("patrimonio_baixar_ativo", {
    p_command_id: commandId,
    p_asset_unit_id: assetUnitId,
    p_reason: reason,
  });
}

export function transferirResponsavel(commandId: string, assetUnitId: string, newResponsibleId: string, reason?: string | null) {
  return call<{ asset_unit_id: string; movement_id: string; responsible_id: string }>("patrimonio_transferir_responsavel", {
    p_command_id: commandId,
    p_asset_unit_id: assetUnitId,
    p_new_responsible_id: newResponsibleId,
    p_reason: reason ?? null,
  });
}
