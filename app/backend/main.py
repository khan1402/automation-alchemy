"""
main.py — FastAPI web layer for the backend.
Knows nothing about HOW metrics are gathered — just imports
collect_all() and serves it over HTTP.
"""

from fastapi import FastAPI
import metrics

app = FastAPI()

@app.get("/metrics")
def read_metrics():
    """Return all system facts as JSON."""
    return metrics.collect_all()




