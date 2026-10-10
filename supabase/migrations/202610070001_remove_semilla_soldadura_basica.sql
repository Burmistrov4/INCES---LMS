-- Retira la etiqueta técnica [SEMILLA] de la oferta pública concreta.
-- No se aplica a otras filas de prueba que puedan usar [SEMILLA].
UPDATE public.programs
SET name = 'Soldadura Básica'
WHERE code = 'SEM-SOL-CL'
  AND name = 'Soldadura Básica [SEMILLA]';
