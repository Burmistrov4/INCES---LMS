#!/usr/bin/env node
// ============================================================================
//  Personaliza las plantillas de correo de Supabase Auth
//
//  Reemplaza los textos por defecto (en inglés, genéricos) por versiones en
//  español con la identidad del INCES.
//
//  Por qué un script y no hacerlo a mano en el panel:
//   - Queda versionado: el cambio es reproducible y auditable.
//   - Está en el repositorio: cualquiera del equipo puede reaplicarlo.
//   - Un cambio en el panel no deja rastro ni se puede revisar en un diff.
//
//  Las plantillas usan la sintaxis Go de Supabase ({{ .ConfirmationURL }},
//  {{ .SiteURL }}, etc.). Esos marcadores NO se pueden traducir: son lo que
//  convierte el correo en un enlace funcional.
//
//  Uso:
//    node supabase/personalizar-plantillas.mjs --dry-run   (solo muestra)
//    node supabase/personalizar-plantillas.mjs             (aplica)
//
//  Requiere SUPABASE_ACCESS_TOKEN (token personal, no la clave de servicio:
//  la Management API no acepta `sb_secret_...`).
// ============================================================================

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const REF = 'twdppwnxlnmxkiejbrei';
const SIMULAR = process.argv.includes('--dry-run');

const aqui = dirname(fileURLToPath(import.meta.url));

/** Lee una variable del entorno, con respaldo en backend/.env. */
function variable(nombre) {
  const delEntorno = process.env[nombre]?.trim();
  if (delEntorno) return delEntorno;

  try {
    const env = readFileSync(join(aqui, '..', 'backend', '.env'), 'utf8');
    for (const linea of env.split('\n')) {
      const sinComentario = linea.split('#')[0].trim();
      const corte = sinComentario.indexOf('=');
      if (corte > 0 && sinComentario.slice(0, corte).trim() === nombre) {
        return sinComentario.slice(corte + 1).trim();
      }
    }
  } catch {
    // Sin respaldo disponible: se resuelve con el error de abajo.
  }
  return '';
}

const token = variable('SUPABASE_ACCESS_TOKEN');
if (!token) {
  console.error(
    '\n  Falta SUPABASE_ACCESS_TOKEN.\n' +
      '  Es el token PERSONAL de la Management API (empieza por `sbp_`),\n' +
      '  no la clave de servicio (`sb_secret_...`, que aquí no sirve).\n',
  );
  process.exit(1);
}

// ---------------------------------------------------------------------------
//  Identidad visual compartida
//
//  El INCES no tiene un cliente de correo con CSS personalizado garantizado:
//  Outlook y Hotmail ignoran las hojas de estilo externas. Por eso el diseño va
//  con estilos EN LÍNEA y una tabla, que es el patrón que funciona en todos los
//  clientes. Un `<div>` con `flex` se ve roto en Hotmail.
// ---------------------------------------------------------------------------

const NOMBRE_CENTRO = 'CFS Nacional de Soldadura «Rafael Urdaneta»';
const SEDE = 'INCES La Isabelica';

/** Envuelve el contenido en el marco institucional. */
function marco({ titulo, intro, boton, enlace, cierre }) {
  return `<div style="margin:0;padding:0;background:#f1f5f9;font-family:-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f1f5f9;padding:32px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:12px;overflow:hidden;border:1px solid #e2e8f0;">

          <tr>
            <td style="background:#0f172a;padding:28px 32px;">
              <p style="margin:0;color:#60a5fa;font-size:12px;font-weight:600;letter-spacing:1px;text-transform:uppercase;">Sistema de Gestión Académica</p>
              <h1 style="margin:8px 0 0;color:#ffffff;font-size:21px;font-weight:700;line-height:1.3;">${NOMBRE_CENTRO}</h1>
              <p style="margin:6px 0 0;color:#94a3b8;font-size:13px;">${SEDE}</p>
            </td>
          </tr>

          <tr>
            <td style="padding:32px;">
              <h2 style="margin:0 0 16px;color:#0f172a;font-size:19px;font-weight:700;">${titulo}</h2>
              <p style="margin:0 0 20px;color:#334155;font-size:15px;line-height:1.6;">${intro}</p>

              <table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 24px;">
                <tr>
                  <td align="center" style="background:#2563eb;border-radius:8px;">
                    <a href="${enlace}" style="display:inline-block;padding:14px 32px;color:#ffffff;font-size:15px;font-weight:600;text-decoration:none;">${boton}</a>
                  </td>
                </tr>
              </table>

              <p style="margin:0 0 8px;color:#64748b;font-size:13px;line-height:1.6;">Si el botón no funciona, copia y pega este enlace en tu navegador:</p>
              <p style="margin:0 0 24px;padding:12px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:6px;color:#2563eb;font-size:12px;word-break:break-all;line-height:1.5;">${enlace}</p>

              <p style="margin:0;color:#64748b;font-size:13px;line-height:1.6;">${cierre}</p>
            </td>
          </tr>

          <tr>
            <td style="background:#f8fafc;border-top:1px solid #e2e8f0;padding:20px 32px;">
              <p style="margin:0;color:#94a3b8;font-size:12px;line-height:1.6;">Este mensaje fue enviado automáticamente por el Sistema de Gestión Académica del INCES. No respondas a este correo.</p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</div>`;
}

// ---------------------------------------------------------------------------
//  Plantillas
// ---------------------------------------------------------------------------

const plantillas = [
  {
    clave: 'invite',
    asunto: `Invitación al Sistema de Gestión Académica — ${SEDE}`,
    contenido: marco({
      titulo: 'Has sido invitado al sistema',
      intro:
        'La coordinación del centro de formación te ha habilitado una cuenta en el Sistema de Gestión Académica del INCES. Desde tu cuenta podrás consultar tus aulas asignadas, cargar calificaciones y registrar la asistencia de tus estudiantes.',
      boton: 'Activar mi cuenta',
      enlace: '{{ .ConfirmationURL }}',
      cierre:
        'El enlace caduca en 24 horas por seguridad. Si no esperabas esta invitación, puedes ignorar este mensaje: sin activación, la cuenta permanece inactiva.',
    }),
  },
  {
    clave: 'confirmation',
    asunto: 'Confirma tu correo — Sistema de Gestión Académica INCES',
    contenido: marco({
      titulo: 'Confirma tu correo electrónico',
      intro:
        'Tu inscripción fue registrada correctamente. Falta un paso: confirmar que este correo es tuyo. Al hacerlo, tu solicitud queda formalmente recibida por el centro de formación.',
      boton: 'Confirmar mi correo',
      enlace: '{{ .ConfirmationURL }}',
      cierre:
        'Si no te inscribiste en el INCES La Isabelica, ignora este mensaje. Si el enlace caduca, puedes solicitar la reemisión desde la pantalla de registro.',
    }),
  },
  {
    clave: 'recovery',
    asunto: 'Restablecer tu contraseña — INCES La Isabelica',
    contenido: marco({
      titulo: 'Restablecer tu contraseña',
      intro:
        'Recibimos una solicitud para restablecer la contraseña de tu cuenta. Haz clic en el botón para elegir una nueva.',
      boton: 'Elegir nueva contraseña',
      enlace: '{{ .ConfirmationURL }}',
      cierre:
        'Si no solicitaste este cambio, ignora este correo: tu contraseña actual sigue funcionando. Nadie de la institución te pedirá tu contraseña por teléfono ni por correo.',
    }),
  },
  {
    clave: 'magic_link',
    asunto: 'Tu enlace de acceso — INCES La Isabelica',
    contenido: marco({
      titulo: 'Acceso sin contraseña',
      intro:
        'Usa este enlace para entrar al sistema sin escribir tu contraseña. Es de un solo uso y caduca en pocos minutos.',
      boton: 'Entrar al sistema',
      enlace: '{{ .ConfirmationURL }}',
      cierre:
        'Si no solicitaste este enlace, ignóralo. Nadie puede entrar a tu cuenta con él si no lo usas.',
    }),
  },
  {
    clave: 'email_change',
    asunto: 'Confirma tu nuevo correo — INCES La Isabelica',
    contenido: marco({
      titulo: 'Confirma tu cambio de correo',
      intro:
        'Solicitaste cambiar el correo asociado a tu cuenta. Confirma la dirección nueva para completar el cambio.',
      boton: 'Confirmar correo nuevo',
      enlace: '{{ .ConfirmationURL }}',
      cierre:
        'Si no solicitaste este cambio, avisa a la coordinación: alguien podría estar intentando acceder a tu cuenta.',
    }),
  },
];

// ---------------------------------------------------------------------------

async function aplicar({ clave, asunto, contenido }) {
  const cuerpos = {
    [`mailer_subjects_${clave}`]: asunto,
    [`mailer_templates_${clave}_content`]: contenido,
  };

  const respuesta = await fetch(
    `https://api.supabase.com/v1/projects/${REF}/config/auth`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(cuerpos),
    },
  );

  if (!respuesta.ok) {
    const detalle = await respuesta.text();
    throw new Error(
      `No se pudo aplicar la plantilla «${clave}» (HTTP ${respuesta.status}): ${detalle.slice(0, 300)}`,
    );
  }
}

async function principal() {
  console.log(
    `\n  ${SIMULAR ? 'SIMULACIÓN — no se escribirá nada' : 'Aplicando plantillas en español'}\n  Proyecto: ${REF}\n`,
  );

  for (const plantilla of plantillas) {
    if (SIMULAR) {
      console.log(`  [simulado] ${plantilla.clave}`);
      console.log(`             asunto: ${plantilla.asunto}`);
      continue;
    }
    try {
      await aplicar(plantilla);
      console.log(`  ✓ ${plantilla.clave}`);
    } catch (error) {
      console.error(`  ✗ ${error.message}`);
      process.exitCode = 1;
    }
  }

  if (!SIMULAR) {
    console.log(
      '\n  Listo. Verifica en: Authentication → Email Templates del panel.\n',
    );
  }
}

await principal();
