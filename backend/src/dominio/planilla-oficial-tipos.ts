/**
 * Contrato semántico de la Planilla Oficial INCES (612 × 792 pt, 1 página).
 *
 * El renderer oficial (`planilla-oficial-pdf.ts`) NO conoce claves JSONB,
 * ni códigos de Supabase, ni etiquetas de PostgREST: recibe este contrato
 * estructurado y dibuja en coordenadas absolutas medidas.
 */

export interface CabeceraOficial {
  fecha: string | null;
  numeroPreimpreso: string | null;
  proyecto: string | null;
  espacioIntegralSocialista: string | null;
  horario: string | null;
}

export interface IdentidadOficial {
  primerNombre: string | null;
  segundoNombre: string | null;
  primerApellido: string | null;
  segundoApellido: string | null;
  cedula: string | null;
  nacionalidad: string | null;
}

export interface NacimientoOficial {
  fecha: string | null; // Formato YYYY-MM-DD o DD/MM/YYYY
  dia: string | null;
  mes: string | null;
  anio: string | null;
  edad: number | null;
}

export interface PuebloIndigenaOficial {
  pertenece: boolean | null;
  cual: string | null;
}

export interface DiscapacidadOficial {
  fisicaMano: boolean;
  fisicaPiernas: boolean;
  sensorialAuditiva: boolean;
  sensorialCeguera: boolean;
  debilidadIntelectual: boolean;
  ninguna: boolean;
  indiqueCual: string | null;
}

export interface ItemPractica {
  valor: string | null;
  desde: string | null;
}

export interface PracticasOficial {
  deporte: ItemPractica;
  cultural: ItemPractica;
  organizacion: ItemPractica;
}

export interface UbicacionOficial {
  estado: string | null;
  municipio: string | null;
  parroquia: string | null;
  comunidad: string | null;
  direccion: string | null;
  telefonoCelular: string | null;
  telefonoFijo: string | null;
  email: string | null;
  twitter: string | null;
  facebook: string | null;
}

export interface FamiliarOficial {
  cedula: string | null;
  nombres: string | null;
  apellidos: string | null;
  fechaNac: string | null;
  genero: 'F' | 'M' | null;
  parentesco: string | null;
  diversidadFuncional: string | null;
  estadoCivil: string | null;
}

export interface MisionOficial {
  codigo: string;
  etiqueta: string;
  marcada: boolean;
  desde: string | null;
}

export type EstadoAvanceFormacion = 'CULMINO' | 'NO_COMPLETO' | 'EN_PROGRESO' | null;

export interface FormacionOficial {
  nivelEducativo: string | null;
  estadoAvance: EstadoAvanceFormacion;
  ultimoAnio: string | null;
  especialidad: string | null;
}

export interface OtraFormacionOficial {
  descripcion: string | null;
}

export interface ExperienciaOficial {
  area: string | null;
  tiempoMeses: string | null;
  portafolio: boolean | null;
  enlace: string | null;
}

export interface PlanillaOficialData {
  cabecera: CabeceraOficial;
  identidad: IdentidadOficial;
  nacimiento: NacimientoOficial;
  sexo: 'F' | 'M' | null;
  estadoCivil: 'SOLTERO' | 'CASADO' | 'DIVORCIADO' | 'VIUDO' | 'CONCUBINATO' | null;
  puebloIndigena: PuebloIndigenaOficial;
  discapacidad: DiscapacidadOficial;
  practicas: PracticasOficial;
  ubicacion: UbicacionOficial;
  familiares: FamiliarOficial[];
  misiones: MisionOficial[]; // Exactamente las 20 misiones
  formacion: FormacionOficial;
  otrasFormaciones: OtraFormacionOficial[];
  experiencias: ExperienciaOficial[];
}

export interface ContextoPlanillaOficial {
  cabecera?: Partial<CabeceraOficial>;
}
