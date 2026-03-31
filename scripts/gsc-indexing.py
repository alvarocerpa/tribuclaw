#!/usr/bin/env python3
"""
Script para solicitar indexación de URLs usando Google Search Console API
Usa Service Account para autenticación sin interacción del usuario

INSTALACIÓN:
pip install google-api-python-client google-auth-httplib2

USO:
python gsc-indexing.py              # Ver estado de URLs
python gsc-indexing.py --submit     # Solicitar indexación
python gsc-indexing.py --sitemap    # Reenviar sitemap
"""

import os
import json
import argparse
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

# Configuración
SERVICE_ACCOUNT_FILE = os.path.expanduser('~/.openclaw/secrets/gsc-service-account.json')
PROPERTY_URL = 'sc-domain:tribuclaw.com'
SCOPES = [
    'https://www.googleapis.com/auth/webmasters',
    'https://www.googleapis.com/auth/indexing',
]

def get_credentials():
    """Autentica con Service Account y devuelve las credenciales"""
    return service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE, scopes=SCOPES)

def get_gsc_service(credentials):
    """Devuelve el servicio de Google Search Console"""
    return build('searchconsole', 'v1', credentials=credentials)

def get_indexing_service(credentials):
    """Devuelve el servicio de Google Indexing API"""
    return build('indexing', 'v3', credentials=credentials)

def get_sitemap_urls():
    """Extrae URLs del sitemap local"""
    import xml.etree.ElementTree as ET
    
    sitemap_path = os.path.expanduser('~/.openclaw/workspace/tribuclaw-web/dist/sitemap-0.xml')
    if not os.path.exists(sitemap_path):
        print(f"Error: No se encuentra el sitemap en {sitemap_path}")
        return []
    
    tree = ET.parse(sitemap_path)
    root = tree.getroot()
    
    ns = {'sm': 'http://www.sitemaps.org/schemas/sitemap/0.9'}
    urls = [loc.text for loc in root.findall('.//sm:loc', ns)]
    return urls

def check_indexing_status(service, url):
    """Verifica el estado de indexación de una URL"""
    try:
        request = service.urlInspection().index().inspect(
            body={
                'inspectionUrl': url,
                'siteUrl': PROPERTY_URL
            }
        )
        response = request.execute()
        
        result = response.get('inspectionResult', {})
        index_status = result.get('indexStatusResult', {})
        
        return {
            'url': url,
            'verdict': index_status.get('verdict', 'UNKNOWN'),
            'coverage_state': index_status.get('coverageState', 'UNKNOWN'),
            'last_crawled': index_status.get('lastCrawlTime', 'Never'),
            'indexable': index_status.get('verdict') == 'PASS'
        }
    except HttpError as e:
        return {'url': url, 'error': str(e)}

def request_indexing(indexing_service, url):
    """Solicita indexación de una URL via Google Indexing API"""
    try:
        request = indexing_service.urlNotifications().publish(
            body={
                'url': url,
                'type': 'URL_UPDATED'
            }
        )
        response = request.execute()
        return {'url': url, 'status': 'submitted', 'response': response}
    except HttpError as e:
        return {'url': url, 'error': str(e)}

def submit_sitemap(service):
    """Reenvía el sitemap a Google"""
    try:
        sitemap_url = "https://tribuclaw.com/sitemap-index.xml"
        request = service.sitemaps().submit(
            siteUrl=PROPERTY_URL,
            feedpath=sitemap_url
        )
        response = request.execute()
        return {'status': 'success', 'sitemap': sitemap_url, 'response': response}
    except HttpError as e:
        return {'status': 'error', 'error': str(e)}

def main():
    parser = argparse.ArgumentParser(description='Gestionar indexación en Google Search Console')
    parser.add_argument('--submit', action='store_true', help='Solicitar indexación de URLs')
    parser.add_argument('--sitemap', action='store_true', help='Reenviar sitemap')
    parser.add_argument('--url', type=str, help='URL específica a procesar')
    args = parser.parse_args()
    
    print("Conectando con Google Search Console...")
    credentials = get_credentials()
    gsc_service = get_gsc_service(credentials)
    indexing_service = get_indexing_service(credentials)
    
    # Obtener URLs
    if args.url:
        urls = [args.url]
    else:
        urls = get_sitemap_urls()
    
    if not urls:
        print("No hay URLs para procesar")
        return
    
    print(f"Procesando {len(urls)} URLs...\n")
    
    if args.sitemap:
        result = submit_sitemap(gsc_service)
        print(f"Reenvío de sitemap: {result}")
        return
    
    results = {'indexed': 0, 'pending': 0, 'errors': 0}
    
    for url in urls:
        if args.submit:
            result = request_indexing(indexing_service, url)
            if 'error' in result:
                print(f"❌ {url}: {result['error']}")
                results['errors'] += 1
            else:
                print(f"✓ {url}: Indexación solicitada")
                results['indexed'] += 1
        else:
            result = check_indexing_status(gsc_service, url)
            if 'error' in result:
                print(f"❌ {url}: {result['error']}")
                results['errors'] += 1
            elif result.get('indexable'):
                print(f"✓ {url}: INDEXADA")
                results['indexed'] += 1
            else:
                status = result.get('coverage_state', 'Unknown')
                print(f"⏳ {url}: {status}")
                results['pending'] += 1
    
    print(f"\n=== RESUMEN ===")
    print(f"Indexadas: {results['indexed']}")
    print(f"Pendientes: {results['pending']}")
    print(f"Errores: {results['errors']}")

if __name__ == '__main__':
    main()
