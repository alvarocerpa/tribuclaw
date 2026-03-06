// @ts-check
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';
import { defineConfig } from 'astro/config';

export default defineConfig({
	site: 'https://tribuclaw.com',
	integrations: [
		mdx(),
		sitemap({
			// Configuración por defecto para todas las URLs
			// Esto añade lastmod, changefreq y priority a todas las páginas
			changefreq: 'weekly',
			priority: 0.7,
			lastmod: new Date(),
		}),
	],
	markdown: {
		shikiConfig: {
			theme: 'github-dark',
		},
	},
});
