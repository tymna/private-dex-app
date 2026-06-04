// Minimal browser shim for Node's `tty`. bb.js only probes `tty.isatty()` to decide
// whether to colorize log output; in a browser there's no TTY, so always false.
export function isatty(): boolean {
  return false
}
export default { isatty }
