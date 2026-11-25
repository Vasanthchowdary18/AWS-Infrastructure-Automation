"""Simple Python web application with health checks and Prometheus metrics."""
import os
import socket
import time

from flask import Flask, Response, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

APP_VERSION = os.getenv("APP_VERSION", "dev")
START_TIME = time.time()

REQUEST_COUNT = Counter(
    "app_http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)
REQUEST_LATENCY = Histogram(
    "app_http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["endpoint"],
)


def create_app() -> Flask:
    app = Flask(__name__)

    @app.before_request
    def _start_timer():
        request._start_time = time.time()

    @app.after_request
    def _record_metrics(response):
        if request.path != "/metrics":
            elapsed = time.time() - getattr(request, "_start_time", time.time())
            REQUEST_LATENCY.labels(endpoint=request.path).observe(elapsed)
            REQUEST_COUNT.labels(
                method=request.method,
                endpoint=request.path,
                status=response.status_code,
            ).inc()
        return response

    @app.get("/")
    def index():
        return jsonify(
            message="Hello from the DevOps demo app!",
            version=APP_VERSION,
            host=socket.gethostname(),
        )

    @app.get("/health")
    def health():
        """Liveness probe: the process is up."""
        return jsonify(status="ok", uptime_seconds=round(time.time() - START_TIME, 2))

    @app.get("/ready")
    def ready():
        """Readiness probe: the app can serve traffic."""
        return jsonify(status="ready")

    @app.get("/api/add")
    def add():
        try:
            a = float(request.args.get("a", ""))
            b = float(request.args.get("b", ""))
        except ValueError:
            return jsonify(error="query params 'a' and 'b' must be numbers"), 400
        return jsonify(result=a + b)

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
