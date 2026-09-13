import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: ['dist/**', 'node_modules/**', 'coverage/**'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: {
      // Sin esto, `no-undef` marca `process`, `console`, `Buffer` o `fetch`
      // como variables inexistentes: son globales de Node, no del lenguaje.
      globals: { ...globals.node },
    },
    rules: {
      // El prefijo `_` marca parámetros deliberadamente ignorados (p. ej. `reply`
      // en un handler que sólo devuelve un valor).
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      // El backend maneja JSON sin tipar en los bordes; prohibir `any` a secas
      // obligaría a castear en sitios donde no aporta seguridad real.
      '@typescript-eslint/no-explicit-any': 'warn',
      eqeqeq: ['error', 'always', { null: 'ignore' }],
      'no-console': 'off',
    },
  },
  {
    // Los guiones de `supabase/` y `test-humo.mjs` son JavaScript puro, no
    // TypeScript, y no pasan por `tsc`. Se excluyen del analizador de tipos,
    // que si no los rechaza por no tener `project`.
    files: ['**/*.mjs'],
    ...tseslint.configs.disableTypeChecked,
  },
);
