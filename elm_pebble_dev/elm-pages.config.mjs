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
<script data-name="BMC-Widget" data-cfasync="false" src="https://cdnjs.buymeacoffee.com/1.0.0/widget.prod.min.js" data-id="fzpmCkhiUf" data-description="Support me on Buy me a coffee!" data-message="" data-color="#5F7FFF" data-position="Right" data-x_margin="18" data-y_margin="18"></script>
`;
  },
  preloadTagForFile(file) {
    // add preload directives for JS assets and font assets, etc., skip for CSS files
    // this function will be called with each file that is processed by Vite, including any files in your headTagsTemplate in your config
    return !file.endsWith(".css");
  },
};
