#!/bin/bash
# Script para desplegar optimizaciones SEO y acelerar indexación

set -e

echo "========================================="
echo "TribuClaw - Despliegue de Optimizaciones SEO"
echo "========================================="
echo ""

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

cd "$(dirname "$0")/.."

echo -e "${YELLOW}[1/6]${NC} Limpiando build anterior..."
rm -rf dist/

echo -e "${YELLOW}[2/6]${NC} Reconstruyendo proyecto con sitemap optimizado..."
npm run build

echo -e "${YELLOW}[3/6]${NC} Verificando sitemap generado..."
if [ -f "dist/sitemap-0.xml" ]; then
    echo "✓ Sitemap generado exitosamente"
    echo ""
    echo "Muestra del sitemap:"
    head -20 dist/sitemap-0.xml
    echo ""
else
    echo -e "${RED}✗ Error: Sitemap no generado${NC}"
    exit 1
fi

echo -e "${YELLOW}[4/6]${NC} Verificando robots.txt..."
if [ -f "dist/robots.txt" ]; then
    echo "✓ robots.txt generado"
    cat dist/robots.txt
    echo ""
else
    echo -e "${RED}✗ Error: robots.txt no generado${NC}"
    exit 1
fi

echo -e "${YELLOW}[5/6]${NC} Verificando Schema.org en home..."
if grep -q "application/ld+json" dist/index.html; then
    echo "✓ Structured data encontrado en home"
else
    echo -e "${YELLOW}⚠ Advertencia: No se encontró structured data en home${NC}"
fi

echo ""
echo -e "${YELLOW}[6/6]${NC} Opciones de despliegue:"
echo ""
echo "A. Desplegar a producción (Cloudflare)"
echo "   Ejecutar: ./autopublish-deploy.sh"
echo ""
echo "B. Verificar localmente"
echo "   Ejecutar: npm run preview"
echo ""
echo "C. Solicitar indexación después del despliegue:"
echo ""
echo "   Opción 1 - IndexNow (rápido):"
echo "   1. Generar API key: https://www.bing.com/indexnow/apikey"
echo "   2. Crear archivo /public/{tu-api-key}.txt con el API key"
echo "   3. Configurar scripts/indexnow-submit.py con tu API key"
echo "   4. Ejecutar: cd scripts && python indexnow-submit.py"
echo ""
echo "   Opción 2 - Google Search Console API:"
echo "   1. Configurar credenciales OAuth (ver documentación)"
echo "   2. Ejecutar: cd scripts && python gsc-indexing.py"
echo ""
echo "   Opción 3 - Manual en GSC UI:"
echo "   1. Ir a: https://search.google.com/search-console"
echo "   2. Usar herramienta 'Inspección de URL' para cada página"
echo "   3. Reenviar sitemap en la sección Sitemaps"
echo ""

echo -e "${GREEN}✓ Optimizaciones SEO listas para desplegar${NC}"
echo ""
echo "Documentación completa: ~/.openclaw/workspace-kimo/memory/research/tribuclaw-seo-indexacion.md"
