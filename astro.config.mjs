// @ts-check
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';
import { defineConfig } from 'astro/config';

export default defineConfig({
	site: 'https://tribuclaw.com',
	integrations: [
		mdx(),
		sitemap({
			changefreq: 'weekly',
			priority: 0.7,
			lastmod: new Date(),
			filter: (page) => !page.includes('/membresia'),
			serialize(item) {
				// Homepage: 1.0
				if (item.url === 'https://tribuclaw.com/' || item.url === 'https://tribuclaw.com') {
					item.priority = 1.0;
					item.changefreq = 'daily';
				}
				// Blog index: 0.8
				else if (item.url === 'https://tribuclaw.com/blog/' || item.url === 'https://tribuclaw.com/blog') {
					item.priority = 0.8;
				}
				// About: 0.5
				else if (item.url.includes('/about')) {
					item.priority = 0.5;
				}
				// Legal pages: 0.3
				else if (item.url.includes('/privacidad') || item.url.includes('/aviso-legal') || item.url.includes('/cookies')) {
					item.priority = 0.3;
				}
				// Pillar posts: 0.8 (will be overridden below if needed)
				// Regular blog posts: 0.6
				else if (item.url.includes('/blog/')) {
					item.priority = 0.6;
					item.changefreq = 'monthly';
				}
				return item;
			},
		}),
	],
	markdown: {
		shikiConfig: {
			theme: 'github-dark',
		},
	},
});
