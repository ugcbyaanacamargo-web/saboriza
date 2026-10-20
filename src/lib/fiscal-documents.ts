export const FISCAL_STATUSES = ["NAO_EMITIDO", "PROCESSANDO", "AUTORIZADA", "REJEITADA", "CANCELADA"] as const;
export type FiscalDocStatus = (typeof FISCAL_STATUSES)[number];

export const STUCK_PROCESSING_HOURS = 24;

export interface FiscalDocumentRow {
  id: string;
  status: string;
  provider: string | null;
  number: string | null;
  externalId: string | null;
  pdfRef: string | null;
  xmlRef: string | null;
  createdAt: string;
  updatedAt: string;
}

export const FISCAL_STATUS_LABEL: Record<FiscalDocStatus, string> = {
  NAO_EMITIDO: "Não emitida",
  PROCESSANDO: "Processando",
  AUTORIZADA: "Autorizada",
  REJEITADA: "Rejeitada",
  CANCELADA: "Cancelada",
};

export function isKnownFiscalStatus(status: string): status is FiscalDocStatus {
  return (FISCAL_STATUSES as readonly string[]).includes(status);
}

export function countByStatus(docs: FiscalDocumentRow[]): Record<FiscalDocStatus, number> {
  const counts = { NAO_EMITIDO: 0, PROCESSANDO: 0, AUTORIZADA: 0, REJEITADA: 0, CANCELADA: 0 };
  for (const doc of docs) {
    if (isKnownFiscalStatus(doc.status)) counts[doc.status] += 1;
  }
  return counts;
}

export function isStuckProcessing(doc: FiscalDocumentRow, now: Date, thresholdHours = STUCK_PROCESSING_HOURS): boolean {
  if (doc.status !== "PROCESSANDO") return false;
  const reference = new Date(doc.updatedAt || doc.createdAt).getTime();
  if (Number.isNaN(reference)) return false;
  return now.getTime() - reference >= thresholdHours * 3_600_000;
}

export function listProviders(docs: FiscalDocumentRow[]): string[] {
  const set = new Set<string>();
  for (const doc of docs) if (doc.provider) set.add(doc.provider);
  return [...set].sort();
}

export const NO_PROVIDER = "__SEM_PROVEDOR__";

export function filterDocuments(docs: FiscalDocumentRow[], status: string | null, provider: string | null): FiscalDocumentRow[] {
  return docs.filter((doc) => {
    if (status && doc.status !== status) return false;
    if (provider === NO_PROVIDER) return !doc.provider;
    if (provider && doc.provider !== provider) return false;
    return true;
  });
}

export function toHttpLink(ref: string | null): string | null {
  if (!ref) return null;
  return /^https?:\/\//i.test(ref.trim()) ? ref.trim() : null;
}
