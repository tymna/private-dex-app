// Deterministic ESM shim for the CJS `detect-node` package (its browser build is
// `module.exports = false`). Vite's optimizer synthesizes the `default` export for this
// inconsistently (works one bundle, breaks the next), causing intermittent
// `does not provide an export named 'default'` crashes from Aztec's pino logger.
// We're always in a browser here, so node-detection is simply false.
export default false
