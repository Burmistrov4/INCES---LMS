import { expect, test } from '@playwright/test';
import { LoginPage } from '../src/pages/LoginPage.js';

const ADMIN = process.env.E2E_ADMIN_EMAIL ?? '';
const PASSWORD = process.env.E2E_ADMIN_PASSWORD ?? '';

const MODULOS = [
  'Auditoría de Accesos',
  'Cuadrante y Horarios',
  'Espacios y Aulas',
  'Guardias Docentes',
  'Inscripciones y Cupos',
  'Lapsos Académicos',
  'Programas Académicos',
  'Secciones',
] as const;

test.describe.serial('CPanel P0 — carga real de módulos administrativos', () => {
  test.skip(ADMIN === '' || PASSWORD === '', 'Faltan credenciales E2E de administrador.');

  test('inicia sesión como administrador real', async ({ page }) => {
    const login = new LoginPage(page);
    await login.abrir();
    await login.entrar(ADMIN, PASSWORD);
  });

  for (const modulo of MODULOS) {
    test('carga ' + modulo + ' sin error de pantalla', async ({ page }) => {
      const login = new LoginPage(page);
      if ((await login.app.cuantos('Inscripciones y Cupos')) === 0) {
        await login.abrir();
        await login.entrar(ADMIN, PASSWORD);
      }

      await login.app.pulsarReal(modulo, { tiempoLimiteMs: 15000 });

      await expect
        .poll(async () => login.app.cuantos(modulo), {
          timeout: 30_000,
          message: 'El módulo no apareció después de navegar.\n' + (await login.app.diagnostico()),
        })
        .toBeGreaterThan(0);

      const errores = await login.app.cuantos('Error al cargar');
      const servidor = await login.app.cuantos('problema interno');
      expect(errores + servidor, 'La pantalla muestra un error de carga visible.\n' + (await login.app.diagnostico())).toBe(0);
    });
  }

  test('Usuarios y Roles expone gestión real, no sólo invitaciones', async ({ page }) => {
    const login = new LoginPage(page);
    if ((await login.app.cuantos('Inscripciones y Cupos')) === 0) {
      await login.abrir();
      await login.entrar(ADMIN, PASSWORD);
    }

    await login.app.pulsarReal('Usuarios y Roles', { tiempoLimiteMs: 15000 });

    await expect.poll(async () => login.app.cuantos('Usuarios y Roles'), { timeout: 30_000 }).toBeGreaterThan(0);

    // El buscador se comprueba con `campo()` y **no** con `cuantos()`: medido el
    // 2026-10-09, `cuantos('Buscar usuario')` da **0** aunque el campo exista, porque
    // `cuantos` sólo mira controles con rol `button|link|tab|menuitem` o hojas de
    // texto, y un `textbox` no es ninguna de las dos cosas. El campo real es un
    // `input[aria-label]` dentro de `flt-semantics`, que es lo que resuelve `campo`.
    await expect.poll(async () => login.app.campo('Buscar usuario').count(), { timeout: 30_000 }).toBeGreaterThan(0);
    await expect.poll(async () => login.app.cuantos('Administradores'), { timeout: 30_000 }).toBeGreaterThan(0);
    await expect.poll(async () => login.app.cuantos('Cambiar rol'), { timeout: 30_000 }).toBeGreaterThan(0);
  });
});
