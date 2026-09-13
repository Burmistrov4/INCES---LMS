/**
 * Cambia el proveedor de correo de Supabase del servicio por defecto a SMTP
 * propio (Resend), y comprueba que el cambio surtió efecto.
 *
 * **Por qué esto no es una mejora opcional.** Con el proveedor por defecto,
 * Supabase aplica tres limitaciones a la vez, y las tres tienen la misma raíz:
 *
 *   1. Los correos salen de `no-reply@mail.app.supabase.io`, un dominio que los
 *      filtros de spam tienen en listas negras por ser genérico y compartido.
 *   2. `rate_limit_email_sent` es 2 por hora. Dos. Todo el onboarding docente
 *      cabe en dos correos.
 *   3. **No se pueden editar las plantillas** — la Management API responde
 *      HTTP 400 con `Email template modification is not available for free tier
 *      projects using the default email provider`. Las plantillas en español
 *      son, literalmente, imposibles hasta que exista SMTP propio.
 *
 * Los tres síntomas se ven distintos desde fuera ("no llega", "llega en inglés",
 * "sólo llegan dos"). Arreglarlos por separado habría sido trabajo perdido.
 *
 * **Sobre `smtp_admin_email`:** importa más de lo que parece. Supabase enruta
 * por ahí los avisos internos del proyecto, y Resend en su dominio de pruebas
 * SÓLO permite enviar al correo dueño de la cuenta. Si se pone un correo
 * distinto del que registró Resend, los envíos fallan con 550.
 *
 * Uso:
 *   node supabase/configurar-smtp.mjs                    # simulación
 *   node supabase/configurar-smtp.mjs --confirmar        # aplica
 *   node supabase/configurar-smtp.mjs --remitente=algo@midominio.com --confirmar
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');

function variable(nombre) {
  const delEntorno = (process.env[nombre] ?? '').trim();
  if (delEntorno.length > 0) return delEntorno;

  try {
    const contenido = readFileSync(join(RAIZ, 'backend', '.env'), 'utf8');
    for (const linea of contenido.split('\n')) {
      const sinComentario = linea.split('#')[0].trim();
      const corte = sinComentario.indexOf('=');
      if (corte > 0 && sinComentario.slice(0, corte).trim() === nombre) {
        return sinComentario.slice(corte + 1).trim();
      }
    }
  } catch {
    // Sin archivo: se decide abajo con el mensaje de error.
  }
  return '';
}

/** Argumento de la forma `--clave=valor`. */
function argumento(nombre) {
  const prefijo = `--${nombre}=`;
  const encontrado = process.argv.find((a) => a.startsWith(prefijo));
  return encontrado ? encontrado.slice(prefijo.length).trim() : '';
}

const REF = 'twdppwnxlnmxkiejbrei';
const CONFIRMAR = process.argv.includes('--confirmar');

const token = variable('SUPABASE_ACCESS_TOKEN');
const apiKey = variable('RESEND_API_KEY');

if (!token) {
  console.error(
    '\n  Falta SUPABASE_ACCESS_TOKEN.\n' +
      '  Es el token PERSONAL de la Management API (empieza por `sbp_`).\n' +
      '  La clave de servicio del proyecto (sb_secret_...) NO sirve aquí.\n',
  );
  process.exit(1);
}
if (!apiKey) {
  console.error(
    '\n  Falta RESEND_API_KEY en backend/.env.\n' +
      '  Resend → API Keys → Create API Key, con permiso «Sending access».\n',
  );
  process.exit(1);
}

// `smtp_admin_email` es el buzón dueño de la cuenta de Resend. Se puede
// sobreescribir con --remitente= cuando haya un dominio verificado.
const remitente =
  argumento('remitente') || 'lorenzo-roca11@hotmail.com';
const nombreRemitente = argumento('nombre') || 'INCES La Isabelica';

const configuracion = {
  // Resend expone SMTP en este host; la contraseña es la propia API key.
  smtp_host: 'smtp.resend.com',
  smtp_port: '465',
  smtp_user: 'resend',
  smtp_pass: apiKey,
  smtp_admin_email: remitente,
  smtp_sender_name: nombreRemitente,
  // Al haber SMTP propio, el límite por defecto (2/hora) es artificialmente
  // bajo: está pensado para el proveedor compartido. 30/hora es holgado para
  // un centro de formación y sigue siendo un tope sensato contra un bucle.
  rate_limit_email_sent: 30,
  // Mantiene la confirmación por correo obligatoria (regla ya establecida).
  mailer_autoconfirm: false,
};

console.log(
  `\n  Proyecto   : ${REF}` +
    `\n  Modo       : ${CONFIRMAR ? 'APLICAR (escribe)' : 'SIMULACIÓN (no escribe)'}` +
    `\n  Remitente  : ${nombreRemitente} <${remitente}>` +
    `\n  Host SMTP  : ${configuracion.smtp_host}:${configuracion.smtp_port}\n`,
);

const visibles = { ...configuracion, smtp_pass: `${apiKey.slice(0, 8)}…(${apiKey.length} car.)` };
console.table(visibles);

if (!CONFIRMAR) {
  console.log('\n  Para aplicar de verdad:\n    node supabase/configurar-smtp.mjs --confirmar\n');
  process.exit(0);
}

const respuesta = await fetch(
  `https://api.supabase.com/v1/projects/${REF}/config/auth`,
  {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(configuracion),
  },
);

if (!respuesta.ok) {
  const detalle = await respuesta.text();
  console.error(`\n  Falló (HTTP ${respuesta.status}):\n  ${detalle.slice(0, 500)}\n`);
  process.exit(1);
}

// ── Comprobación: se RELEE la configuración, no se confía en el 200 ──────────
// Un PATCH que responde 200 pero no aplica el campo existe (pasó con los
// módulos del Administrador Maestro). Leer lo que quedó guardado es la única
// forma de saber que el cambio es real.
const verificacion = await fetch(
  `https://api.supabase.com/v1/projects/${REF}/config/auth`,
  { headers: { Authorization: `Bearer ${token}` } },
);
const estado = await verificacion.json();

console.log('\n  Verificación (lo que quedó guardado de verdad):');
const esperado = {
  smtp_host: configuracion.smtp_host,
  smtp_user: configuracion.smtp_user,
  smtp_admin_email: configuracion.smtp_admin_email,
  smtp_sender_name: configuracion.smtp_sender_name,
  rate_limit_email_sent: configuracion.rate_limit_email_sent,
};

let todoBien = true;
for (const [clave, valor] of Object.entries(esperado)) {
  const real = estado[clave];
  // La contraseña nunca la devuelve la API, por eso no se compara aquí.
  const coincide = String(real) === String(valor);
  if (!coincide) todoBien = false;
  console.log(`    ${coincide ? '✓' : '✗'} ${clave.padEnd(24)} ${real ?? '(vacío)'}`);
}

console.log(
  todoBien
    ? '\n  SMTP propio activo. Ahora sí se pueden aplicar las plantillas:\n' +
        '    node supabase/personalizar-plantillas.mjs\n'
    : '\n  ATENCIÓN: algún campo no quedó como se pidió. Revísalo en el panel antes de\n' +
        '  seguir: si `smtp_host` está vacío, las plantillas seguirán dando HTTP 400.\n',
);

process.exitCode = todoBien ? 0 : 1;
