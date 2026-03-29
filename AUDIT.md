# Auditoría TribuClaw Web — 2026-03-29

## Estructura de páginas
- `/` (index.astro) — Landing principal ✓
- `/about/` — About page ✓ contenido real
- `/blog/` — Blog index ✓
- `/blog/[slug]` — Posts individuales ✓
- `/membresia/` — **ELIMINAR** (redundante con pricing en home)
- `/rss.xml` — Feed ✓

## Problemas encontrados

### Prioridad 1 — Crashes
- Console JS: null checks correctos (`if (!body) return`, `if (!canvas) return`)
- GSAP/ScrollTrigger: registros correctos
- Lenis: integración ok, pero **doble llamada a lenis.raf** (una via requestAnimationFrame manual y otra via gsap.ticker.add) — esto puede causar scroll irregular
- No hay errores de encoding visibles

### Prioridad 2 — Membresía
- `membresia.astro` existe con contenido completo de pricing
- Footer enlaza a `/membresia/` ← **ROTO si se elimina**
- Header NO enlaza a membresía ✓
- Un blog post menciona "membresia" pero como texto, no link

### Prioridad 3 — Blog CTAs
- BlogPost.astro solo tiene CTA al final (texto inline)
- No hay CTAs intercalados en el contenido
- Necesita 2-3 CTAs visuales tipo banner

### Prioridad 4 — Mockups/Estética
- Hero: consola terminal mockup ✓ (buena)
- App section: solo texto + iconos, **falta mockup visual**
- Testimonios: solo 2 tarjetas, peso visual bajo
- No hay mockup CSS para la app

### Prioridad 5 — About
- Contenido real y coherente ✓
- Fundador con LinkedIn ✓
- Missión clara ✓

### Prioridad 6 — Flujo
- Lenis doble raf es un bug
- Responsive: el console se oculta en <480px (correcto)
- Lazy loading: imágenes usan loading="lazy" donde corresponde

## Plan de implementación
1. Fix Lenis doble raf
2. membresia.astro → redirect a WHOP_URL
3. Footer: cambiar link /membresia/ → #pricing
4. BlogPost: añadir CTA components intercalados
5. App section: mockup CSS
6. Testimonios: más peso visual
7. Build + Deploy
