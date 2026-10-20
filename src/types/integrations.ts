export type IntegrationProvider = "ASAAS" | "FISCAL" | "BASE";
export type IntegrationEnvironment = "SANDBOX" | "PRODUCAO";
export type IntegrationStatus = "NAO_CONFIGURADO" | "CONFIGURADO" | "VALIDADO" | "ERRO";

export interface IntegrationCredential {
  id: string;
  provider: IntegrationProvider;
  environment: IntegrationEnvironment;
  keyLast4: string | null;
  walletId: string | null;
  fiscalProviderName: string | null;
  status: IntegrationStatus;
  isActive: boolean;
  activatedAt: string | null;
  lastValidatedAt: string | null;
  lastError: string | null;
  hasWebhookToken: boolean;
  updatedAt: string;
}

export interface IntegrationEvent {
  id: string;
  provider: IntegrationProvider;
  eventType: string;
  environment: IntegrationEnvironment | null;
  receivedAt: string;
  processedAt: string | null;
  processError: string | null;
}

export type FiscalMissingCode =
  | "informacoes_fiscais"
  | "inscricao_municipal"
  | "cnae"
  | "item_lista_servicos"
  | "certificado_digital"
  | "token_acesso"
  | "usuario_senha";

export interface FiscalInfoSummary {
  configured: boolean;
  missing: FiscalMissingCode[];
  municipalChecked: boolean;
}

export const FISCAL_MISSING_LABEL: Record<FiscalMissingCode, string> = {
  informacoes_fiscais: "informações fiscais da empresa",
  inscricao_municipal: "inscrição municipal",
  cnae: "CNAE",
  item_lista_servicos: "item da lista de serviços",
  certificado_digital: "certificado digital",
  token_acesso: "token de acesso da prefeitura",
  usuario_senha: "usuário e senha da prefeitura",
};

export type ConnectionErrorKind = "CREDENTIAL" | "CONNECTION";

export type EnvironmentState = "NAO_CONFIGURADO" | "CHAVE_SALVA" | "CONEXAO_VALIDA" | "ATIVO" | "ERRO_CREDENCIAL";
