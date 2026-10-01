"""
main.py — FastAPI web layer for the frontend.
Calls the backend's /metrics endpoint and renders the result as HTML.
"""
import os
import socket
import httpx
from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

app = FastAPI()
templates = Jinja2Templates(directory="templates")

# Serve style.css (and any future static assets) at /static/...
app.mount("/static", StaticFiles(directory="static"), name="static")

# Read the backend URL from an environment variable, with a fallback
# default for local testing.
BACKEND_URL = os.environ.get("BACKEND_URL", "http://192.168.56.13:3000")


@app.api_route("/", methods=["GET", "HEAD"])
def home(request: Request):
    """Fetch metrics from the backend and render them on a webpage."""
    response = httpx.get(f"{BACKEND_URL}/metrics")
    backend_data = response.json()

    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "web_server_hostname": socket.gethostname(),
            "data": backend_data
        }
    )
    
    

    