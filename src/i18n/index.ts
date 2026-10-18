import en from "./en.json";

/**
 * Minimal i18n for Milestone 1: static English strings behind a lookup that
 * is ready for more locales. Runtime language switching arrives with the
 * settings milestone, where it becomes reactive.
 */
const dictionaries = { en } as const;

export type Locale = keyof typeof dictionaries;

let current: Locale = "en";

function lookup(dictionary: unknown, key: string): string | undefined {
  let node: unknown = dictionary;
  for (const part of key.split(".")) {
    if (typeof node !== "object" || node === null || !(part in node)) {
      return undefined;
    }
    node = (node as Record<string, unknown>)[part];
  }
  return typeof node === "string" ? node : undefined;
}

/** Translate `key` in the active locale, falling back to English. */
export function t(key: string): string {
  return lookup(dictionaries[current], key) ?? lookup(dictionaries.en, key) ?? key;
}

export function setLocale(locale: Locale): void {
  current = locale;
}

export function getLocale(): Locale {
  return current;
}
