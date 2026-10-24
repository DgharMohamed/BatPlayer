/**
 * BatSoft external links shown in About, and the safe way to open them.
 *
 * Opening goes through the Rust `open_external` command, which only accepts
 * absolute http(s) URLs and hands them to the OS default browser. The
 * webview never navigates itself to an external site.
 */
import { invoke } from "@tauri-apps/api/core";

/** The app's page on the BatSoft site. */
export const appWebsite = "https://batsoft.vercel.app/apps/batplayer";
/** Terms of Service. */
export const termsUrl = "https://batsoft.vercel.app/apps/batplayer/terms";
/** Privacy Policy. */
export const privacyUrl = "https://batsoft.vercel.app/apps/batplayer/privacy";

/** Opens an external http(s) URL in the default browser. */
export function openExternal(url: string): Promise<void> {
  return invoke("open_external", { url });
}
