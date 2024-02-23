import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import Backend from "i18next-http-backend";
import { isDevBuild } from "@/utils/env";
import { getUserLocales } from "get-user-locale";
import { includes } from "@/utils/type-guards";

/**
 * Load translations.
 *
 * Localization and related concerns (aka "internationalization", or "i18n") for
 * our apps is handled by i18n framework.
 *
 * In addition to the base i18next package, we use two of its plugins:
 *
 * - i18next-http-backend, for loading the JSON files containin the translations
 *   at runtime, and
 *
 * - react-i18next, which adds React specific APIs
 */
export const setupI18n = async (savedLocaleString?: string) => {
    const lng = getBestPossibleUserLocale(savedLocaleString);
    // https://www.i18next.com/overview/api
    await i18n
        // i18next-http-backend: Asynchronously loads translations over HTTP
        // https://github.com/i18next/i18next-http-backend
        .use(Backend)
        // react-i18next: React support
        // Pass the i18n instance to react-i18next.
        .use(initReactI18next)
        // Initialize i18next
        // Option docs: https://www.i18next.com/overview/configuration-options
        .init({
            debug: isDevBuild,
            returnEmptyString: false,
            fallbackLng: "en",
            lng: lng,
            interpolation: {
                escapeValue: false, // not needed for react as it escapes by default
            },
            react: {
                useSuspense: false,
                transKeepBasicHtmlNodesFor: [
                    "div",
                    "strong",
                    "h2",
                    "span",
                    "code",
                    "p",
                    "br",
                ],
            },
            load: "languageOnly",
        });

    i18n.services.formatter?.add("dateTime", (value, lng) => {
        return new Date(value / 1000).toLocaleDateString(lng, {
            year: "numeric",
            month: "long",
            day: "numeric",
        });
    });
};

/**
 * List of all {@link SupportedLocale}s.
 *
 * Locales are combinations of a language code, and an optional region code.
 *
 * For example, "en", "en-US", "en-IN" (Indian English), "pt" (Portuguese),
 * "pt-BR" (Brazilian Portuguese).
 *
 * In our Crowdin Project, we have work-in-progress translations into more
 * languages than this. When a translation reaches a high enough coverage, say
 * 90%, then we manually add it to this list of supported languages.
 */
export const supportedLocales = ["en", "fr", "zh", "nl", "es"] as const;
/** The type of  {@link supportedLocale}s. */
export type SupportedLocale = (typeof supportedLocales)[number];

/**
 * Return the current locale in which our user interface is being shown.
 *
 * Note that this may be different from the user's locale. For example, the
 * browser might be set to en-GB, but since we don't support that specific
 * variant of English, this value will be (say) en-US.
 */
export const currentLocale = () => {
    const locale = i18n.resolvedLanguage;
    return locale && includes(supportedLocales, locale) ? locale : "en";
};

/** Enums of supported locale */
export enum Language {
    en = "en",
    fr = "fr",
    zh = "zh",
    nl = "nl",
    es = "es",
}

export function getBestPossibleUserLocale(
    savedLocaleString?: string,
): Language {
    switch (savedLocaleString) {
        case "en":
            return Language.en;
        case "fr":
            return Language.fr;
        case "zh":
            return Language.zh;
        case "nl":
            return Language.nl;
        case "es":
            return Language.es;
    }

    const userLocales = getUserLocales();
    for (const lc of userLocales) {
        if (lc.startsWith("en")) {
            return Language.en;
        } else if (lc.startsWith("fr")) {
            return Language.fr;
        } else if (lc.startsWith("zh")) {
            return Language.zh;
        } else if (lc.startsWith("nl")) {
            return Language.nl;
        } else if (lc.startsWith("es")) {
            return Language.es;
        }
    }
    return Language.en;
}
