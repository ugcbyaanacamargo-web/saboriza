export function isValidCnae(value: string): boolean {
  return /^\d{7}$/.test(value.trim());
}

export function isValidMunicipalRegistration(value: string): boolean {
  const trimmed = value.trim();
  return trimmed === "" || /^[A-Za-z0-9./-]{1,20}$/.test(trimmed);
}

export function isValidMunicipalServiceCode(value: string): boolean {
  return value.trim().length <= 20;
}

export function validateFiscalFields(fields: {
  cnaeCode: string;
  municipalRegistration: string;
  municipalServiceCode: string;
}): string | null {
  if (fields.cnaeCode.trim() !== "" && !isValidCnae(fields.cnaeCode)) return "CNAE deve ter 7 dígitos numéricos.";
  if (!isValidMunicipalRegistration(fields.municipalRegistration)) {
    return "Inscrição municipal deve ser alfanumérica (letras, números, ponto, hífen ou barra).";
  }
  if (!isValidMunicipalServiceCode(fields.municipalServiceCode)) return "Código de serviço municipal deve ter até 20 caracteres.";
  return null;
}
