#!/usr/bin/env python3
"""
Verificar y solicitar indexación de URLs en Google Search Console
"""
import os
import sys
import xml.etree.ElementTree as ET
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

SERVICE_ACCOUNT_FILE = os.path.expanduser('~/.openclaw/secrets/gsc-service-account.json')
SCOPES = ['https://www.googleapis.com/auth/webmasters']
PROPERTY_URL = 'sc-domain:tribuclaw.com'

def get_service():
    credentials = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE, scopes=SCOPES)
    return build('searchconsole', 'v1', credentials=credentials)

def get_sitemap_urls():
    sitemap_path = os.path.expanduser('~/.openclaw/workspace/tribuclaw-web/dist/sitemap-0.xml')
    tree = ET.parse(sitemap_path)
    root = tree.getroot()
    ns = {'sm': 'http://www.sitemaps.org/schemas/sitemap/0.9'}
    return [loc.text for loc in root.findall('.//sm:loc', ns)]

def check_url(service, url):
    try:
        request = service.urlInspection().index().inspect(
            body={'inspectionUrl': url, 'siteUrl': PROPERTY_URL}
        )
        response = request.execute()
        result = response.get('inspectionResult', {}).get('indexStatusResult', {})
        return {
            'url': url,
            'verdict': result.get('verdict', 'UNKNOWN'),
            'coverage': result.get('coverageState', 'Unknown'),
            'indexed': result.get('verdict') == 'PASS'
        }
    except HttpError as e:
        return {'url': url, 'error': str(e), 'indexed': False}

def request_indexing(service, url):
    try:
        request = service.urlNotifications().publish(
            body={'url': url, 'type': 'URL_UPDATED'}
        )
        response = request.execute()
        return {'url': url, 'success': True}
    except HttpError as e:
        if 'QUOTA_EXCEEDED' in str(e):
            return {'url': url, 'success': False, 'reason': 'quota'}
        return {'url': url, 'success': False, 'reason': str(e)}

def main():
    print("Conectando con Google Search Console...")
    service = get_service()
    
    urls = get_sitemap_urls()
    print(f"Verificando {len(urls)} URLs...\n")
    
    indexed = []
    pending = []
    errors = []
    
    for i, url in enumerate(urls, 1):
        result = check_url(service, url)
        status = "✓" if result.get('indexed') else "⏳"
        coverage = result.get('coverage', result.get('error', 'Unknown'))[:50]
        print(f"[{i}/{len(urls)}] {status} {url.split('/')[-1] or '/'}: {coverage}")
        
        if result.get('indexed'):
            indexed.append(url)
        elif 'error' in result:
            errors.append(result)
        else:
            pending.append(url)
    
    print(f"\n{'='*50}")
    print(f"Indexadas: {len(indexed)}")
    print(f"Pendientes: {len(pending)}")
    print(f"Errores: {len(errors)}")
    
    if pending and '--submit' in sys.argv:
        print(f"\nSolicitando indexación de {len(pending)} URLs...")
        for url in pending[:10]:  # Límite de cuota
            result = request_indexing(service, url)
            if result.get('success'):
                print(f"  ✓ {url}")
            else:
                print(f"  ✗ {url}: {result.get('reason')}")

if __name__ == '__main__':
    main()
