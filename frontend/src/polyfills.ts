// Node-global polyfills for the browser. Aztec's bb.js (grumpkin/prover) and some
// foundation utils assume Node's `Buffer` exists. This module is imported FIRST in
// main.tsx so the globals are set before any @aztec module evaluates (ES imports run
// in source order, depth-first — so a side-effect import placed first wins).
import { Buffer } from 'buffer'

globalThis.Buffer ??= Buffer
// some deps reference a bare `global`; `define: { global: 'globalThis' }` in vite.config
// handles the compile-time token, this covers any runtime property lookups.
;(globalThis as unknown as { global: typeof globalThis }).global ??= globalThis
