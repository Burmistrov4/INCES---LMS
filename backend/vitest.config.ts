import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts'],
    reporters: ['default'],

    // En Windows, la recolección de módulos de TypeScript puede tardar decenas
    // de segundos (disco + resolución de ESM). El primer `inject()` de cada
    // archivo paga ese coste, así que el límite por defecto de 5 s provoca
    // fallos falsos. No se trata de un test lento: es el arranque.
    testTimeout: 30_000,
    hookTimeout: 30_000,

    // Menos hilos: cada uno vuelve a resolver el grafo de módulos, y en esta
    // máquina el cuello de botella es el sistema de archivos, no la CPU.
    pool: 'threads',
    poolOptions: { threads: { minThreads: 1, maxThreads: 2 } },
  },
});
