import { isValidCnpj } from "@/lib/cnpj";
import { isValidCpf, onlyDigits } from "@/lib/cpf";

export type FiscalChoice = "EMITIR_NFE" | "EMITIR_NFE_PRODUTO" | "SEM_DOCUMENTO_FISCAL";

export function isEmitChoice(choice: FiscalChoice): boolean {
  return choice === "EMITIR_NFE" || choice === "EMITIR_NFE_PRODUTO";
}

export function fiscalEmissionFunction(choice: FiscalChoice): "asaas-emit-invoice" | "base-create-invoice" | null {
  if (choice === "EMITIR_NFE") return "asaas-emit-invoice";
  if (choice === "EMITIR_NFE_PRODUTO") return "base-create-invoice";
  return null;
}

export function fiscalDocumentName(choice: FiscalChoice): string {
  if (choice === "EMITIR_NFE") return "NFS-e";
  if (choice === "EMITIR_NFE_PRODUTO") return "NF-e de produto";
  return "documento fiscal";
}

export interface ProductNfeProductInfo {
  name: string;
  ncm: string | null;
  saleUnit: string | null;
}

export interface ProductNfeCustomerInfo {
  document: string | null;
  baseCustomerId: string | null;
}

export function hasValidDocument(value: string | null | undefined): boolean {
  if (!value) return false;
  const digits = onlyDigits(value);
  if (digits.length === 11) return isValidCpf(digits);
  if (digits.length === 14) return isValidCnpj(digits);
  return false;
}

export function productNfePendencies(products: ProductNfeProductInfo[], customer: ProductNfeCustomerInfo | null): string[] {
  const pending: string[] = [];
  if (products.length === 0) pending.push("Pedido sem itens para compor a NF-e.");
  if (!customer) pending.push("Cliente do pedido não encontrado.");
  else if (!customer.baseCustomerId && !hasValidDocument(customer.document)) pending.push("Cliente sem CPF/CNPJ válido cadastrado.");
  for (const p of products) {
    if (!p.ncm?.trim()) pending.push(`Produto "${p.name}" sem NCM cadastrado.`);
    if (!p.saleUnit?.trim()) pending.push(`Produto "${p.name}" sem unidade de venda (ex.: UN, CX, KG).`);
  }
  return pending;
}

export interface BaseCredentialInfo {
  provider: string;
  isActive: boolean;
}

export const PRODUCT_NFE_UNAVAILABLE_REASON = "Integração Base não configurada/ativa em Configurações > Integrações.";

export function isProductNfeAvailable(credentials: BaseCredentialInfo[] | null | undefined): boolean {
  return (credentials ?? []).some((c) => c.provider === "BASE" && c.isActive);
}

export function resolveFiscalChoice(choice: FiscalChoice, productNfeAvailable: boolean): FiscalChoice {
  return choice === "EMITIR_NFE_PRODUTO" && !productNfeAvailable ? "EMITIR_NFE" : choice;
}

export function emissionFailureMessage(
  choice: FiscalChoice,
  error: { message?: string } | null | undefined,
  data: { error?: unknown } | null | undefined
): string | null {
  const detail = error?.message ?? (typeof data?.error === "string" && data.error ? data.error : data?.error ? "erro desconhecido" : null);
  if (!detail) return null;
  return `Pedido confirmado, mas a ${fiscalDocumentName(choice)} não foi emitida (${detail}). A nota ficou como NAO_EMITIDO e pode ser reemitida.`;
}
