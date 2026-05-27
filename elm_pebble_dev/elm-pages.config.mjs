import { defineConfig } from "vite";
import adapter from "elm-pages/adapter/netlify.js";
import elmTailwind from "elm-tailwind-classes/vite";
import tailwindcss from "@tailwindcss/vite";

export default {
  vite: defineConfig({
    plugins: [elmTailwind(), tailwindcss()],
  }),
  adapter,
  headTagsTemplate(context) {
    return `
<meta name="generator" content="elm-pages v${context.cliVersion}" />
<meta name="color-scheme" content="light dark" />
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
<link rel="icon" type="image/png" sizes="96x96" href="/favicon-96x96.png" />
<link rel="shortcut icon" href="/favicon.ico" />
<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png" />
<link rel="manifest" href="/site.webmanifest" />
<script>
  (() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");

    const applyTheme = () => {
      const saved = localStorage.getItem("theme");
      const useDark = saved === "dark" || (!saved && media.matches);
      document.documentElement.classList.toggle("dark", useDark);
    };

    applyTheme();
    media.addEventListener("change", applyTheme);
  })();
</script>
    <style>
      @media (max-width: 47.99rem) { header .site-header-desktop-nav { display: none !important; } }
      @media (min-width: 48rem) { header .site-header-mobile-menu { display: none !important; } }
      .site-header-mobile-menu details:not([open]) > nav { display: none !important; }
      .site-hero-layout { display: flex !important; flex-direction: column !important; width: 100%; }
      .site-hero-intro { display: flex !important; flex-flow: row nowrap !important; align-items: flex-start !important; gap: 1.5rem; width: 100%; }
      .site-hero-headlines { flex: 1 1 0% !important; min-width: 0; }
      .site-hero-photo { flex: 0 0 14rem !important; width: 14rem !important; max-width: 14rem !important; overflow: hidden; }
      .site-hero-photo picture, .site-hero-photo img { display: block; width: 14rem !important; max-width: 14rem !important; height: auto !important; }
      header ~ main section picture img[src*="pebble-elm"] { display: block !important; width: 14rem !important; max-width: 14rem !important; height: auto !important; }
    </style>
    <script data-name="BMC-Widget" data-cfasync="false" src="https://cdnjs.buymeacoffee.com/1.0.0/widget.prod.min.js" data-id="fzpmCkhiUf" data-description="Support me on Buy me a coffee!" data-message="" data-color="#5F7FFF" data-position="Right" data-x_margin="18" data-y_margin="18"></script>
    <script src="https://sdk.feedback.one/v0/core.min.js" data-project-id="019e3269-74e1-7a61-8e62-27959f5d5442" defer></script>
`;
  },
  preloadTagForFile(file) {
    // add preload directives for JS assets and font assets, etc., skip for CSS files
    // this function will be called with each file that is processed by Vite, including any files in your headTagsTemplate in your config
    return !file.endsWith(".css");
  },
};
