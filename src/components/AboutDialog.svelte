<script lang="ts">
  import { onMount } from "svelte";
  import packageInfo from "../../package.json";
  import BatLogo from "./BatLogo.svelte";
  import { t } from "../i18n";
  import { appWebsite, termsUrl, privacyUrl, openExternal } from "../api/links";

  interface Props {
    onclose: () => void;
  }

  let { onclose }: Props = $props();
  let dialogEl: HTMLElement | undefined = $state();

  const features = [
    "about.features.formats",
    "about.features.controls",
    "about.features.playlists",
    "about.features.tracks",
    "about.features.display",
    "about.features.snapshots",
  ];

  const links = [
    { url: appWebsite, key: "about.links.app" },
    { url: termsUrl, key: "about.links.terms" },
    { url: privacyUrl, key: "about.links.privacy" },
  ];

  onMount(() => dialogEl?.focus());

  function openLink(event: MouseEvent, url: string): void {
    event.preventDefault();
    openExternal(url).catch((err) => console.error("failed to open url", url, err));
  }

  function onDialogKeydown(event: KeyboardEvent): void {
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      onclose();
      return;
    }

    if (event.key === "Tab" && dialogEl) {
      const focusable = [...dialogEl.querySelectorAll<HTMLElement>(
        'button:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])',
      )];
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (!first || !last) return;
      if (event.shiftKey && (document.activeElement === first || document.activeElement === dialogEl)) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && (document.activeElement === last || document.activeElement === dialogEl)) {
        event.preventDefault();
        first.focus();
      }
    }
  }
</script>

<div
  class="backdrop"
  role="presentation"
  onclick={(event) => {
    if (event.target === event.currentTarget) onclose();
  }}
>
  <dialog
    open
    class="dialog"
    aria-modal="true"
    aria-labelledby="about-title"
    aria-describedby="about-description"
    tabindex="-1"
    bind:this={dialogEl}
    onkeydown={onDialogKeydown}
  >
    <button class="close" type="button" title={t("about.close")} aria-label={t("about.close")} onclick={onclose}>
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18" /></svg>
    </button>

    <div class="identity">
      <BatLogo size={112} />
      <div class="eyebrow">{t("about.eyebrow")}</div>
      <h1 id="about-title">{t("app.name")}</h1>
      <p id="about-description">{t("about.description")}</p>
      <span class="version">{t("about.version")} {packageInfo.version}</span>
      <nav class="links" aria-label="External links">
        {#each links as link}
          <a
            href={link.url}
            target="_blank"
            rel="noreferrer noopener"
            onclick={(event) => openLink(event, link.url)}
          >{t(link.key)}</a>
        {/each}
      </nav>
    </div>

    <div class="details">
      <h2>{t("about.featuresTitle")}</h2>
      <ul>
        {#each features as feature}
          <li>{t(feature)}</li>
        {/each}
      </ul>
      <div class="technology">
        <span>{t("about.builtWith")}</span>
        <strong>Tauri 2</strong>
        <span class="dot" aria-hidden="true">·</span>
        <strong>libmpv</strong>
      </div>
    </div>

    <footer>{t("about.footer")}</footer>
  </dialog>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 100;
    display: grid;
    place-items: center;
    padding: 24px;
    background: rgba(0, 0, 0, 0.68);
    backdrop-filter: blur(8px);
    animation: fade-in 140ms ease both;
  }

  .dialog {
    position: relative;
    margin: 0;
    width: min(560px, 100%);
    max-height: min(760px, 100%);
    overflow: auto;
    padding: 0;
    border: 1px solid var(--border);
    border-radius: 16px;
    background: linear-gradient(155deg, #1a1a20, var(--bg-elevated) 58%);
    color: var(--text);
    box-shadow: 0 28px 90px rgba(0, 0, 0, 0.62);
    outline: none;
    animation: rise-in 180ms ease both;
  }

  .close {
    position: absolute;
    top: 14px;
    right: 14px;
    z-index: 1;
    display: grid;
    width: 32px;
    height: 32px;
    place-items: center;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.04);
    color: var(--text-dim);
    cursor: pointer;
  }

  .close svg {
    width: 16px;
    height: 16px;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.8;
    stroke-linecap: round;
  }

  .close:hover,
  .close:focus-visible {
    border-color: var(--accent-soft);
    color: var(--accent);
    outline: none;
  }

  .identity {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 38px 36px 28px;
    text-align: center;
  }

  .identity :global(.bat-logo) {
    width: 112px;
    height: auto;
    margin: 0 0 12px;
    filter: drop-shadow(0 7px 24px rgba(255, 212, 0, 0.16));
  }

  .eyebrow {
    color: var(--accent);
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.16em;
    text-transform: uppercase;
  }

  h1 {
    margin: 6px 0 8px;
    font-size: 30px;
    letter-spacing: -0.04em;
  }

  .identity p {
    max-width: 390px;
    margin: 0;
    color: var(--text-dim);
    font-size: 14px;
    line-height: 1.6;
  }

  .version {
    margin-top: 16px;
    padding: 5px 10px;
    border: 1px solid var(--border);
    border-radius: 999px;
    color: var(--text-dim);
    font-size: 11px;
    font-variant-numeric: tabular-nums;
  }

  .links {
    display: flex;
    align-items: center;
    gap: 16px;
    margin-top: 20px;
    font-size: 12px;
  }

  .links a {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 5px 12px;
    border: 1px solid var(--border);
    border-radius: 999px;
    color: var(--text-dim);
    text-decoration: none;
    transition: color 120ms ease, border-color 120ms ease, background 120ms ease;
  }

  .links a::before {
    width: 10px;
    height: 10px;
    flex: none;
    /* small external-arrow glyph drawn inline */
    background: currentColor;
    content: "";
    clip-path: polygon(
      20% 0,
      100% 0,
      100% 80%,
      84% 80%,
      84% 28%,
      12% 100%,
      0 88%,
      72% 16%,
      20% 16%
    );
    opacity: 0.75;
  }

  .links a:hover,
  .links a:focus-visible {
    border-color: var(--accent-soft);
    background: rgba(255, 212, 0, 0.08);
    color: var(--accent);
    outline: none;
  }

  .details {
    padding: 22px 32px 20px;
    border-top: 1px solid var(--border);
    background: rgba(0, 0, 0, 0.12);
  }

  h2 {
    margin: 0 0 14px;
    font-size: 13px;
    font-weight: 650;
  }

  ul {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 11px 18px;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  li {
    display: flex;
    align-items: flex-start;
    gap: 9px;
    color: var(--text-dim);
    font-size: 12px;
    line-height: 1.45;
  }

  li::before {
    width: 6px;
    height: 6px;
    flex: none;
    margin-top: 5px;
    border-radius: 50%;
    background: var(--accent);
    content: "";
    box-shadow: 0 0 10px var(--accent-soft);
  }

  .technology {
    display: flex;
    align-items: center;
    gap: 9px;
    margin-top: 22px;
    padding-top: 16px;
    border-top: 1px solid var(--border);
    color: var(--text-faint);
    font-size: 11px;
  }

  .technology strong {
    color: var(--text-dim);
    font-weight: 600;
  }

  .dot { color: var(--accent); }

  footer {
    padding: 14px 24px 18px;
    color: var(--text-faint);
    font-size: 11px;
    text-align: center;
  }

  @keyframes fade-in { from { opacity: 0; } to { opacity: 1; } }
  @keyframes rise-in {
    from { opacity: 0; transform: translateY(8px) scale(0.99); }
    to { opacity: 1; transform: translateY(0) scale(1); }
  }

  @media (max-width: 480px) {
    .backdrop { padding: 12px; }
    .identity { padding: 34px 22px 24px; }
    .details { padding: 20px; }
    ul { grid-template-columns: 1fr; }
    .links { flex-wrap: wrap; justify-content: center; gap: 10px; }
  }
</style>
