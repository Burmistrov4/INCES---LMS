import type { ContextoPlanillaOficial } from '../dominio/planilla-oficial-tipos.js';
import type { EntradaPlanilla } from './planilla-valores.js';
import { adaptarAPlanillaOficial } from './planilla-oficial-valores.js';
import { renderizarPlanillaOficialPdf } from './planilla-oficial-pdf.js';

/**
 * Puerto de integración de la Planilla Oficial.
 *
 * Mantiene separadas las dos decisiones:
 * 1. cómo se traducen los datos persistidos al contrato institucional;
 * 2. cómo ese contrato se sobreimprime sobre el PDF oficial.
 *
 * La producción actual todavía usa el renderer histórico. Este adaptador permite
 * cambiar únicamente el punto de composición cuando F2 quede validada, sin tocar
 * las rutas HTTP ni el contrato de PuertaPlanilla.
 */
export async function renderizarPlanillaOficialDesdeEntrada(
  entrada: EntradaPlanilla,
  contexto?: ContextoPlanillaOficial,
): Promise<Uint8Array> {
  const datosOficiales = adaptarAPlanillaOficial(entrada, contexto);
  return renderizarPlanillaOficialPdf(datosOficiales);
}
