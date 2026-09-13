/**
 * Envío de correo transaccional.
 *
 * El backend NO guarda contraseñas ni reimplanta un SMTP propio: delega en
 * Resend, que ya está conectado a Supabase Auth (ver `supabase/configurar-smtp.mjs`).
 * Aquí sólo necesitamos enviar el enlace de invitación del profesor.
 *
 * Sin dominio verificado en Resend, el correo SÓLO se entrega a la cuenta dueña
 * del proyecto (Lorenzo: `lorenzoroca333@gmail.com`). Por eso el endpoint de
 * invitación **siempre** devuelve el enlace de activación en la respuesta: el
 * administrador puede usarlo o repartirlo aunque el correo no llegue. El envío
 * real es, en este momento, la vía de lujo; el enlace en la respuesta es la vía
 * que siempre funciona para probar el flujo.
 */

export interface MensajeCorreo {
  para: string;
  asunto: string;
  html: string;
}

export interface ResultadoEnvio {
  /** `true` si Resend aceptó el mensaje. */
  entregado: boolean;
}

export interface EnvioCorreo {
  enviar(mensaje: MensajeCorreo): Promise<ResultadoEnvio>;
}

export interface OpcionesRemitenteResend {
  /** API key de Resend (`re_...`). Sin ella, el envío se considera no entregado. */
  apiKey?: string;
  /** Remitente. Sin dominio verificado, Resend exige `onboarding@resend.dev`. */
  from: string;
}

/**
 * Remitente basado en la API REST de Resend (`https://api.resend.com/emails`).
 *
 * No es bloqueante para el flujo: si Resend falla (sin dominio, sin clave, 403,
 * caída de red) devolvemos `{ entregado: false }` y el llamante decide cómo
 * avisar. Nunca lanzamos: un correo que no llega no debe tumbar la invitación,
 * que ya está persistida y tiene su enlace de respaldo en la respuesta.
 */
export function crearRemitenteResend(opciones: OpcionesRemitenteResend): EnvioCorreo {
  const { apiKey, from } = opciones;

  return {
    async enviar(mensaje: MensajeCorreo): Promise<ResultadoEnvio> {
      if (!apiKey) return { entregado: false };

      try {
        const respuesta = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from,
            to: [mensaje.para],
            subject: mensaje.asunto,
            html: mensaje.html,
          }),
        });

        if (!respuesta.ok) return { entregado: false };
        return { entregado: true };
      } catch {
        return { entregado: false };
      }
    },
  };
}
