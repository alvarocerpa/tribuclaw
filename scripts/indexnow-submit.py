#!/usr/bin/env python3
"""
Script para notificar URLs a IndexNow (Bing, Yandex, Naver, Seznam, Yep)
Documentación: https://www.indexnow.org/documentation
"""

import requests
import json
from typing import List

# Configuración
INDEXNOW_ENDPOINT = "https://www.indexnow.org/indexnow"
# Generar tu API key en: https://www.bing.com/indexnow/apikey
API_KEY = "TU_API_KEY_AQUI"  # REEMPLAZAR CON TU API KEY
HOST = "tribuclaw.com"

# URLs a notificar
URLS_TO_SUBMIT = [
    "https://tribuclaw.com/",
    "https://tribuclaw.com/about/",
    "https://tribuclaw.com/blog/",
    # Añadir aquí las URLs de artículos de blog específicos si necesitas
]

def submit_to_indexnow(url: str) -> dict:
    """Envía una URL individual a IndexNow"""
    payload = {
        "host": HOST,
        "key": API_KEY,
        "url": url
    }

    headers = {
        "Content-Type": "application/json; charset=utf-8"
    }

    try:
        response = requests.post(INDEXNOW_ENDPOINT, json=payload, headers=headers)
        response.raise_for_status()
        return {
            "url": url,
            "status": "success",
            "status_code": response.status_code
        }
    except requests.exceptions.RequestException as e:
        return {
            "url": url,
            "status": "error",
            "error": str(e)
        }

def submit_batch(urls: List[str]) -> dict:
    """Envía múltiples URLs en una sola petición (hasta 10,000)"""
    payload = {
        "host": HOST,
        "key": API_KEY,
        "urlList": urls
    }

    headers = {
        "Content-Type": "application/json; charset=utf-8"
    }

    try:
        response = requests.post(INDEXNOW_ENDPOINT, json=payload, headers=headers)
        response.raise_for_status()
        return {
            "count": len(urls),
            "status": "success",
            "status_code": response.status_code
        }
    except requests.exceptions.RequestException as e:
        return {
            "count": len(urls),
            "status": "error",
            "error": str(e)
        }

def main():
    print("=== IndexNow URL Submission ===\n")

    # Opción 1: Enviar todas las URLs en lote
    print(f"Enviando {len(URLS_TO_SUBMIT)} URLs en lote...")
    result = submit_batch(URLS_TO_SUBMIT)
    print(json.dumps(result, indent=2))

    # Opción 2: Enviar URLs individualmente (para ver cuál falla)
    print("\n\nEnviando URLs individualmente...")
    results = []
    for url in URLS_TO_SUBMIT:
        result = submit_to_indexnow(url)
        results.append(result)
        status_icon = "✓" if result["status"] == "success" else "✗"
        print(f"{status_icon} {url}: {result['status']}")

    # Resumen
    success_count = sum(1 for r in results if r["status"] == "success")
    print(f"\n=== Resumen ===")
    print(f"Éxito: {success_count}/{len(results)}")
    print(f"Errores: {len(results) - success_count}/{len(results)}")

if __name__ == "__main__":
    main()
