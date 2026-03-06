# AUTOPUBLISH.md — Instrucciones para generar y publicar artículos en tribuclaw.com

## Pipeline

1. **Elegir tema**: Leer `tribuclaw-seo/ESTRATEGIA.md` para la lista de artículos planificados. Verificar qué ya existe en `tribuclaw-web/src/content/blog/`. Elegir el siguiente artículo que NO exista todavía, siguiendo el calendario editorial y alternando pilares.

2. **Investigar**: Hacer web_search sobre el tema para datos actualizados, estadísticas, ejemplos reales.

3. **Escribir el .mdx**: Seguir EXACTAMENTE este formato y reglas:

### Frontmatter obligatorio
```yaml
---
title: 'Título en español correcto (con tildes y eñes)'
description: 'Descripción SEO de 150-160 caracteres. Directa, con keyword principal.'
pubDate: YYYY-MM-DD  # fecha de hoy
author: 'Álvaro Cerpa'
pillar: 'agente-ia-personal' | 'automatizacion-ia' | 'emprender-con-ia' | 'openclaw' | 'tribuclaw'
tags: ['tag1', 'tag2', 'tag3']
keywords: ['keyword principal', 'long-tail 1', 'long-tail 2', 'long-tail 3', 'long-tail 4']
faq:
  - q: 'Pregunta frecuente 1'
    a: 'Respuesta concisa pero completa.'
  - q: 'Pregunta frecuente 2'
    a: 'Respuesta concisa pero completa.'
  - q: 'Pregunta frecuente 3'
    a: 'Respuesta concisa pero completa.'
---
```

### REGLA CRITICA sobre frontmatter
- **NO usar tildes ni eñes en los valores YAML del frontmatter** (title, description, faq q/a). Astro MDX parser falla con caracteres especiales en YAML.
- Escribir "Que es" en vez de "Qué es", "automatizacion" en vez de "automatización" en el frontmatter.
- **OBLIGATORIO incluir `heroImage`** en el frontmatter: `heroImage: "/images/blog/hero-{slug}.svg"`. Sin esto, el blog muestra el logo genérico en vez de la imagen del artículo.
- **EN EL CUERPO del artículo SÍ usar tildes y eñes normalmente.**

### Estructura del artículo
```mdx
import CTA from '../../components/CTA.astro';

[Párrafo introductorio potente, sin rodeos, que enganche. 2-3 frases. NO incluir la imagen hero aquí — el layout la renderiza automáticamente desde el frontmatter heroImage.]

## Sección 1 (H2 con keyword)

[Contenido. Cada sección debe funcionar como respuesta independiente para LLMs.]

<CTA />

## Sección 2

[Contenido.]

## Sección 3

[Contenido.]

<CTA />

## Sección 4

[Contenido.]

## Sección 5

[Contenido.]

<CTA />
```

### Reglas de redacción
- **Español castellano correcto** con tildes y eñes en el cuerpo
- **1.500-2.500 palabras** por artículo (pilares: 4.000-6.000)
- **Directo, sin relleno**. Cada frase aporta valor
- **Con opinión**. No neutral. TribuClaw tiene postura
- **Cada sección funciona como respuesta standalone** para LLMs
- **3+ CTAs** intercalados (usar `<CTA />`)
- **3-5 FAQs** en frontmatter (se renderizan automáticamente con Schema)
- **Links internos**: enlazar a otros artículos del blog cuando sea relevante
- **Sin em dashes** (—). Usar puntos, comas o puntos y coma
- **Sin "Great question!" ni fórmulas genéricas**
- **Tono**: el de SOUL.md. Directo, inteligente, con humor cuando encaje

### Nombre del archivo
- Slug en minúsculas, sin tildes, palabras separadas por guiones
- Ejemplo: `como-crear-agente-ia-desde-cero.mdx`

4. **Crear imagen hero SVG** (OBLIGATORIO): SVG infográfico en `public/images/blog/hero-{slug}.svg`. Debe ser profesional, informativo y coherente con el contenido del artículo. Seguir el estándar visual de los mejores heroes existentes (ver ejemplos en `public/images/blog/`).

### Estándar visual para hero SVGs
- **ViewBox**: `0 0 1200 630` (ratio OG image)
- **Fondo**: `#080808` con contenedor rect `#0d0d0d` + stroke `#1a1a1a`
- **Estructura**: Cards, diagramas de flujo, hub-and-spoke, tablas comparativas. Elegir la que mejor represente el contenido del artículo.
- **Datos reales**: Incluir datos, pasos, métricas, nombres de herramientas. Que el hero INFORME, no solo decore.
- **Acento**: `#e94560` para títulos, bordes de cards, iconos
- **Texto**: `#fff` principal, `#888` secundario, `#555` terciario
- **Emojis**: Usar como iconos en los nodos/cards
- **Título del artículo**: Centrado abajo (y=530 aprox), font-size 24, font-weight 700
- **Branding**: `tribuclaw.com` centrado al final (y=560), color `#555`, font-size 12
- **PROHIBIDO**: Heroes genéricos tipo "robot con bloques", formas abstractas sin significado, diseños infantiles o simplistas
- **PROHIBIDO usar emojis unicode en SVGs** (🖥️, 🔐, ⚙️, etc.) — los navegadores no los renderizan dentro de `<img>`. Usar solo texto, formas y colores.
- **NO incluir la imagen hero en el cuerpo del MDX** — el layout BlogPost.astro la renderiza automáticamente desde el frontmatter `heroImage`

### Ejemplos de referencia (de mejor a peor)
- `hero-5-cosas.svg`: 5 cards con datos + caja de resultado. Excelente.
- `hero-openclaw.svg`: Hub central + satélites con conexiones. Excelente.
- `hero-whatsapp.svg`, `hero-ganar-dinero.svg`: Buenos.
- El antiguo `hero-crear-agente.svg` (robot cara con bloques): INACEPTABLE. No repetir.

5. **Crear 2-4 imágenes inline SVG** (OBLIGATORIO): Cada artículo DEBE tener imágenes dentro del cuerpo para enriquecer visualmente. Guardar en `public/images/blog/{slug}-{descriptor}.svg`.

### Estándar visual para inline SVGs
- **ViewBox**: `0 0 800 350-450` (horizontal, legible en móvil)
- **Estilo**: Mismo sistema visual que los heroes (fondo oscuro, cards, datos)
- **Tipos recomendados**: Diagramas de flujo, comparativas, infografías de pasos, hub-and-spoke, tablas visuales
- **Mínimo**: 2 imágenes inline por artículo
- **Colocación**: Después de la sección que ilustran, antes de la siguiente
- **Alt text**: Descriptivo y con keyword cuando sea natural

### En el MDX, insertar con:
```mdx
![Descripción de la imagen](/images/blog/{slug}-{descriptor}.svg)
```

6. **OBLIGATORIO: Añadir `heroImage` en el frontmatter del MDX**: `heroImage: "/images/blog/hero-{slug}.svg"`. Esto es lo que usan los listados del blog y la home para mostrar la imagen. Sin esto, sale el logo genérico. También añadir el mapping en `heroImages` de `src/pages/blog/index.astro` y `src/pages/index.astro` como respaldo.

7. **Build y deploy**:
```bash
cd /home/claw1/.openclaw/workspace/tribuclaw-web
npx astro build
CLOUDFLARE_API_TOKEN=4fZu4AsXIRUwWWuHJjw2bas66OyHOSNO_aC4wuyh CLOUDFLARE_ACCOUNT_ID=014162b37ae770253f6e43c0ba038fdb npx wrangler pages deploy dist --project-name tribuclaw --branch master --commit-dirty=true
```

8. **Verificar build correcto**: Antes de deploy, comprobar que el HTML generado es valido:
```bash
# Verificar que el archivo existe y tiene estructura correcta (debe tener <title>)
head -20 dist/blog/SLUG/index.html | grep -q "<title>" && echo "OK" || echo "ERROR: HTML mal generado"
```

9. **Indexación forzada**: Ejecutar el script de indexación para que los motores lo descubran rápido:
```bash
bash /home/claw1/.openclaw/workspace/tribuclaw-seo/index-ping.sh https://tribuclaw.com/blog/SLUG-DEL-ARTICULO/
```

10. **OBLIGATORIO - Notificar a Álvaro**: Después del deploy exitoso, enviar mensaje a Álvaro confirmando la publicación. Formato: "📝 Nuevo artículo publicado: {título} → https://tribuclaw.com/blog/{slug}/". Usar la herramienta de mensajes de la sesión. NUNCA omitir este paso.

## Ritmo y horarios de publicación

### Reglas anti-patrón (SEO)
- **1 artículo/día** (dominio joven, subir a 2/día cuando tengamos >50 artículos)
- **Horario aleatorio**: cada día publicar a una hora diferente entre 7:00 y 22:00 hora España
- **Saltar ~1 día/semana**: aleatoriamente, no publicar algún día para simular comportamiento humano
- **NUNCA publicar a la misma hora dos días seguidos**
- **Variar longitud**: alternar entre artículos cortos (1.500 palabras) y largos (2.500+)

### Internal linking (OBLIGATORIO)
- Cada artículo nuevo DEBE incluir 2-3 enlaces internos a artículos existentes
- Formato: `[texto ancla descriptivo](/blog/slug-del-articulo/)`
- Insertar de forma natural dentro del texto, NO como lista al final
- Priorizar enlaces a artículos pilar y contenido relacionado temáticamente

## Orden de publicación sugerido (próximos artículos)

Alternar entre pilares. Priorizar artículos con keywords de alta conversión:

1. `como-crear-tu-propio-agente-ia-desde-cero` (Pilar 1)
2. `automatizar-telegram-con-agente-ia` (Pilar 2)
3. `montar-agencia-automatizacion-ia` (Pilar 3)
4. `instalar-openclaw-en-vps-paso-a-paso` (Pilar 4)
5. `agente-ia-personal-vs-chatgpt-diferencias` (Pilar 1)
6. `automatizar-emails-con-ia-sin-perder-el-toque-humano` (Pilar 2)
7. `herramientas-ia-para-emprendedores-2026` (Pilar 3)
8. `openclaw-conectar-whatsapp-tutorial` (Pilar 4)
9. `agente-ia-que-gestiona-tu-whatsapp` (Pilar 1)
10. `automatizar-calendario-con-ia` (Pilar 2)
11. `ia-para-infoproductores-guia-completa` (Pilar 3)
12. `openclaw-vs-chatgpt-vs-copilot-comparativa` (Pilar 4)
13. `agente-ia-que-lee-emails-por-ti` (Pilar 1)
14. `automatizar-redes-sociales-con-ia` (Pilar 2)
15. `caso-real-mi-agente-ia-me-ahorra-4-horas-al-dia` (Pilar 3)
16. `openclaw-skills-que-son-como-instalar` (Pilar 4)
17. `agente-ia-con-memoria-permanente` (Pilar 1)
18. `automatizar-atencion-al-cliente-con-ia` (Pilar 2)
19. `crear-comunidad-de-pago-sobre-ia` (Pilar 3)
20. `openclaw-memoria-como-funciona` (Pilar 4)

## CTA link
Todos los CTAs apuntan a: `https://whop.com/tribu-claw/tribu-claw/`
(Ya está configurado en el componente CTA.astro)
