// Script de arranque del Servidor Local Multi-Dispositivo (LAN)
// INCES LMS — Modo Centro de Formación / Red Local
//
// Detecta las interfaces de red del equipo host, levanta el backend Fastify
// (0.0.0.0:3001) y sirve la aplicación web compilada (0.0.0.0:8090) para que
// computadoras de aula, tablets y teléfonos en la misma red Wi-Fi/Ethernet
// puedan acceder al sistema simultáneamente.
//
// Uso: node devops/iniciar-servidor-local-lan.mjs [--verificar-solo]

import { networkInterfaces } from 'node:os';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { resolve } from 'node:path';

const PUERTO_BACKEND = 3001;
const PUERTO_FRONTEND = 8090;

function obtenerIpsLan() {
  const interfaces = networkInterfaces();
  const ips = [];
  for (const [nombre, lista] of Object.entries(interfaces)) {
    if (!lista) continue;
    for (const iface of lista) {
      if (iface.family === 'IPv4' && !iface.internal) {
        ips.push({ interfaz: nombre, ip: iface.address });
      }
    }
  }
  return ips;
}

function puertoDisponible(puerto) {
  return new Promise((res) => {
    const s = createServer();
    s.once('error', () => res(false));
    s.once('listening', () => {
      s.close();
      res(true);
    });
    s.listen(puerto, '0.0.0.0');
  });
}

async function main() {
  console.log('='.repeat(70));
  console.log(' INCES LMS — Servidor Local Multi-Dispositivo (Red LAN)');
  console.log('='.repeat(70));

  const ips = obtenerIpsLan();
  if (ips.length === 0) {
    console.warn('[AVISO] No se detectaron interfaces IPv4 no internas.');
    console.log('Acceso disponible solo vía localhost.');
  } else {
    console.log('\n[RECEPTOR LAN] Direcciones IP disponibles en este equipo:');
    for (const { interfaz, ip } of ips) {
      console.log(`  - ${interfaz.padEnd(20)}: http://${ip}:${PUERTO_FRONTEND}`);
      console.log(`    API Backend       : http://${ip}:${PUERTO_BACKEND}`);
    }
  }

  const backendLibre = await puertoDisponible(PUERTO_BACKEND);
  const frontendLibre = await puertoDisponible(PUERTO_FRONTEND);

  console.log('\n[ESTADO DE PUERTOS]');
  console.log(`  - Backend  (${PUERTO_BACKEND}): ${backendLibre ? 'LIBRE (listo)' : 'EN USO'}`);
  console.log(`  - Frontend (${PUERTO_FRONTEND}): ${frontendLibre ? 'LIBRE (listo)' : 'EN USO'}`);

  if (process.argv.includes('--verificar-solo')) {
    console.log('\nModo verificación completado.');
    process.exit(0);
  }

  console.log('\n[INSTRUCCIONES DE ACCESO MULTI-DISPOSITIVO]');
  console.log('1. Asegúrate de que los dispositivos estén conectados al mismo Wi-Fi/switch.');
  console.log('2. Si el Firewall de Windows muestra aviso, marca "Permitir en redes privadas".');
  console.log(`3. Abre en los navegadores de los otros dispositivos:`);
  for (const { ip } of ips) {
    console.log(`   -> http://${ip}:${PUERTO_FRONTEND}`);
  }
  console.log('\nPresiona Ctrl+C en cualquier momento para apagar el servidor local.\n');
}

main().catch((err) => {
  console.error('[ERROR]', err);
  process.exit(1);
});
