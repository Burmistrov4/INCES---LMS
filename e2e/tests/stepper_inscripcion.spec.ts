// El Stepper de inscripción se construye desde el catálogo, no desde el código.
//
// **Qué protege.** El formulario del aspirante no tiene los pasos escritos a
// mano: `aspirante_form_screen.dart` los arma con `catalogo.grupos` (`_grupos`) y
// un `for` sobre esa lista, así que **un grupo del catálogo es un paso** y un
// grupo que se queda sin campos desaparece solo (`CatalogoInscripcion.grupos`
// recorre los campos, no una lista de grupos). Eso es una virtud —el CFS cambia
// el formulario desde el panel, sin tocar Flutter— y también un riesgo: si el
// cableado se rompiera, el Stepper mostraría pasos que el catálogo no tiene, o
// dejaría de mostrar los que sí, y ninguna prueba de widgets lo vería porque
// todas usan catálogos falsos.
//
// **Por qué esta prueba es DIFERENCIAL y no una lista fija.** No afirma «los
// pasos son estos nueve». Lee el catálogo por la API —la misma respuesta que
// consume la pantalla— y comprueba que el Stepper muestra **exactamente** esos
// grupos, en ese orden, más el paso de cierre que sí está fijo en Dart. Si el CFS
// añade mañana un campo a un grupo nuevo desde el panel, esta prueba sigue
// pasando —porque el formulario debe seguirlo— y sólo falla si la pantalla se
// desincroniza del catálogo, que es el fallo que de verdad importa.
//
// Medido el 2026-09-29 sobre la app real: el encabezado del paso **activo** es un
// nodo `role="group"` cuyo `aria-label` es `"1\nDatos personales"` (número,
// salto de línea, título), y los encabezados de los pasos **colapsados** son
// botones de 734×72 con el texto `"2 Ubicación y contacto"` como nodo de texto
// directo. Por eso los títulos se normalizan con `\s+ → ' '` antes de comparar, y
// por eso el localizador no puede filtrar por `role="button"`: el paso 1 no lo es.

import { expect, test } from '@playwright/test';

import { FlutterApp } from '../src/pages/FlutterApp';

const BACKEND_URL = process.env.E2E_BACKEND_URL ?? 'http://127.0.0.1:3001';

/**
 * El único paso que **no** viene del catálogo.
 *
 * La contraseña no es un dato de la planilla: es la credencial de la cuenta, así
 * que vive en el Stepper como paso fijo en Dart (`_construirConfirmacion`).
 */
const PASO_DE_CIERRE = 'Confirmación y Contraseña';

test.describe('Stepper de inscripción (M4)', () => {
  test('muestra los grupos del catálogo, en su orden, y el paso de cierre al final', async ({
    page,
    request,
  }) => {
    // --- 1. La fuente de verdad: el catálogo, tal como lo sirve el backend. ---
    const respuesta = await request.get(`${BACKEND_URL}/api/v1/inscripcion/campos`);
    expect(
      respuesta.ok(),
      `el catálogo de campos respondió ${respuesta.status()} — ¿está el backend arriba y ` +
        'encendido el módulo m4_inscripciones?',
    ).toBe(true);

    const cuerpo = (await respuesta.json()) as { campos: Array<{ grupo: string }> };
    expect(Array.isArray(cuerpo.campos), 'la respuesta no trae `campos`').toBe(true);

    // Los grupos, en orden de aparición. `campos` llega ordenado por `orden`, que
    // es global —no por grupo—, así que un grupo aparece donde aparece su primer
    // campo: recorrer en orden y quedarse con la primera vez es exactamente el
    // orden que usa el formulario.
    const grupos: string[] = [];
    for (const campo of cuerpo.campos) {
      if (!grupos.includes(campo.grupo)) grupos.push(campo.grupo);
    }
    expect(grupos.length, 'el catálogo no trajo ningún grupo').toBeGreaterThan(0);

    // --- 2. La app real. ---
    const app = new FlutterApp(page);
    await app.abrir('/#/inscripcion');

    const esperados = [...grupos, PASO_DE_CIERRE].map((nombre, i) => `${i + 1} ${nombre}`);

    // Los títulos no están hasta que la pantalla resuelve el catálogo por red.
    await expect
      .poll(
        async () =>
          (await app.nodos()).filter((n) => /^\d+\s/.test(n.etiqueta.replace(/\s+/g, ' '))).length,
        {
          message:
            'El Stepper no terminó de pintar sus encabezados. Árbol semántico:\n' +
            (await app.volcarSemantica()),
          timeout: 30_000,
        },
      )
      .toBeGreaterThanOrEqual(esperados.length);

    // --- 3. Los encabezados, en orden visual. ---
    //
    // Se toma cualquier nodo cuyo texto EMPIECE por el número del paso: eso
    // cubre el `role="group"` del paso activo y los botones de los colapsados,
    // sin depender de cuál de los dos es cuál.
    const encabezados = (await app.nodos())
      .map((n) => ({ ...n, etiqueta: n.etiqueta.replace(/\s+/g, ' ').trim() }))
      .filter((n) => /^\d+\s\S/.test(n.etiqueta))
      .sort((a, b) => a.y - b.y);

    // Ni uno de menos ni uno de más, y con los títulos exactos.
    expect(
      encabezados.map((n) => n.etiqueta),
      'los pasos que pinta el Stepper no son los grupos del catálogo.\n' +
        'Árbol semántico:\n' +
        (await app.volcarSemantica()),
    ).toEqual(esperados);

    // --- 4. El último paso del catálogo NO es el último del Stepper. ---
    //
    // Se afirma explícitamente porque es la pregunta que originó esta prueba: el
    // paso de cierre va detrás del último grupo. Si alguien reordenara el
    // `steps` del Stepper, la comparación de arriba seguiría pasando —el
    // conjunto es el mismo— y sólo esto lo detectaría.
    expect(encabezados.at(-1)?.etiqueta).toBe(`${esperados.length} ${PASO_DE_CIERRE}`);
    expect(encabezados.at(-2)?.etiqueta).toBe(`${esperados.length - 1} ${grupos.at(-1)}`);
  });
});
