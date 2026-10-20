import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";
import {
  countByStatus,
  filterDocuments,
  FISCAL_STATUSES,
  FISCAL_STATUS_LABEL,
  isKnownFiscalStatus,
  isStuckProcessing,
  listProviders,
  NO_PROVIDER,
  STUCK_PROCESSING_HOURS,
  toHttpLink,
  type FiscalDocumentRow,
} from "@/lib/fiscal-documents";

const STATUS_TONE: Record<string, string> = {
  NAO_EMITIDO: "bg-forest-950/5 text-ink-muted",
  PROCESSANDO: "bg-sky-100 text-sky-700",
  AUTORIZADA: "bg-emerald-100 text-emerald-700",
  REJEITADA: "bg-red-100 text-red-700",
  CANCELADA: "bg-amber-100 text-amber-700",
};

const FETCH_LIMIT = 300;

function formatDate(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

export function FiscalDocumentsPanel({ companyId }: { companyId: string }) {
  const [docs, setDocs] = useState<FiscalDocumentRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string | null>(null);
  const [providerFilter, setProviderFilter] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    void supabase
      .from("fiscal_documents")
      .select("id, status, provider, number, external_id, pdf_ref, xml_ref, created_at, updated_at")
      .eq("company_id", companyId)
      .order("created_at", { ascending: false })
      .limit(FETCH_LIMIT)
      .then(({ data, error: queryError }) => {
        if (cancelled) return;
        if (queryError) {
          setError("Não foi possível carregar os documentos fiscais.");
        } else {
          setError(null);
          setDocs(
            (data ?? []).map((row) => ({
              id: row.id,
              status: row.status,
              provider: row.provider,
              number: row.number,
              externalId: row.external_id,
              pdfRef: row.pdf_ref,
              xmlRef: row.xml_ref,
              createdAt: row.created_at,
              updatedAt: row.updated_at,
            }))
          );
        }
        setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [companyId]);

  const now = useMemo(() => new Date(), [docs]);
  const counts = useMemo(() => countByStatus(docs), [docs]);
  const providers = useMemo(() => listProviders(docs), [docs]);
  const visible = useMemo(() => filterDocuments(docs, statusFilter, providerFilter), [docs, statusFilter, providerFilter]);
  const stuckCount = useMemo(() => docs.filter((d) => isStuckProcessing(d, now)).length, [docs, now]);

  return (
    <div className="flex flex-col gap-4 rounded-2xl border border-forest-950/10 bg-white p-5">
      <div>
        <h3 className="font-bold text-forest-950">Notas emitidas</h3>
        <p className="mt-1 text-sm text-ink-muted">Consulta das notas fiscais da empresa. Somente leitura.</p>
      </div>

      <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
        {FISCAL_STATUSES.map((status) => (
          <button
            key={status}
            type="button"
            onClick={() => setStatusFilter(statusFilter === status ? null : status)}
            className={`min-h-[44px] rounded-xl border px-3 py-2 text-left ${statusFilter === status ? "border-forest-950" : "border-forest-950/10"}`}
          >
            <span className="block text-xl font-extrabold text-forest-950">{counts[status]}</span>
            <span className="block text-xs text-ink-muted">{FISCAL_STATUS_LABEL[status]}</span>
          </button>
        ))}
      </div>

      {stuckCount > 0 && (
        <p className="rounded-xl bg-amber-50 px-3 py-2 text-sm text-amber-800">
          {stuckCount} {stuckCount === 1 ? "nota está" : "notas estão"} em processamento há mais de {STUCK_PROCESSING_HOURS}h. Vale conferir no provedor.
        </p>
      )}

      <div className="flex flex-wrap gap-3">
        <label className="flex flex-col gap-1 text-xs text-ink-muted">
          Status
          <select
            value={statusFilter ?? ""}
            onChange={(e) => setStatusFilter(e.target.value || null)}
            className="min-h-[44px] rounded-xl border border-forest-950/10 bg-white px-3 text-sm text-forest-950"
          >
            <option value="">Todos</option>
            {FISCAL_STATUSES.map((status) => (
              <option key={status} value={status}>{FISCAL_STATUS_LABEL[status]}</option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs text-ink-muted">
          Provedor
          <select
            value={providerFilter ?? ""}
            onChange={(e) => setProviderFilter(e.target.value || null)}
            className="min-h-[44px] rounded-xl border border-forest-950/10 bg-white px-3 text-sm text-forest-950"
          >
            <option value="">Todos</option>
            {providers.map((provider) => (
              <option key={provider} value={provider}>{provider}</option>
            ))}
            <option value={NO_PROVIDER}>Sem provedor</option>
          </select>
        </label>
      </div>

      {error && <p className="rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
      {loading && <p className="text-sm text-ink-muted">Carregando notas…</p>}
      {!loading && !error && visible.length === 0 && <p className="text-sm text-ink-muted">Nenhuma nota encontrada.</p>}

      {visible.length > 0 && (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[640px] text-left text-sm">
            <thead>
              <tr className="border-b border-forest-950/10 text-xs uppercase text-ink-muted">
                <th className="py-2 pr-3">Número</th>
                <th className="py-2 pr-3">Status</th>
                <th className="py-2 pr-3">Provedor</th>
                <th className="py-2 pr-3">Data</th>
                <th className="py-2">Arquivos</th>
              </tr>
            </thead>
            <tbody>
              {visible.map((doc) => {
                const stuck = isStuckProcessing(doc, now);
                const rejected = doc.status === "REJEITADA";
                const pdf = toHttpLink(doc.pdfRef);
                const xml = toHttpLink(doc.xmlRef);
                return (
                  <tr key={doc.id} className={`border-b border-forest-950/5 ${rejected ? "bg-red-50" : stuck ? "bg-amber-50" : ""}`}>
                    <td className="py-2 pr-3 font-mono text-xs">{doc.number ?? doc.externalId ?? "—"}</td>
                    <td className="py-2 pr-3">
                      <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${STATUS_TONE[doc.status] ?? "bg-forest-950/5 text-ink-muted"}`}>
                        {isKnownFiscalStatus(doc.status) ? FISCAL_STATUS_LABEL[doc.status] : doc.status}
                      </span>
                      {stuck && <span className="ml-2 text-xs font-semibold text-amber-700">parada</span>}
                    </td>
                    <td className="py-2 pr-3">{doc.provider ?? "—"}</td>
                    <td className="whitespace-nowrap py-2 pr-3">{formatDate(doc.createdAt)}</td>
                    <td className="py-2">
                      <div className="flex gap-3">
                        {pdf && <a href={pdf} target="_blank" rel="noreferrer" className="font-semibold text-forest-950 underline">PDF</a>}
                        {xml && <a href={xml} target="_blank" rel="noreferrer" className="font-semibold text-forest-950 underline">XML</a>}
                        {!pdf && !xml && <span className="text-ink-muted">—</span>}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {docs.length >= FETCH_LIMIT && (
        <p className="text-xs text-ink-muted">Mostrando as {FETCH_LIMIT} notas mais recentes.</p>
      )}

      <p className="rounded-xl bg-forest-950/5 px-3 py-2 text-xs text-ink-muted">
        Reemissão de notas rejeitadas ou paradas ainda não está disponível nesta tela.
      </p>
    </div>
  );
}
