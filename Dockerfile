# ---------- build stage ----------
FROM python:3.12-slim AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------- runtime stage ----------
FROM python:3.12-slim
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --create-home appuser

WORKDIR /app
COPY --from=build /install /usr/local
COPY app/ ./app/

USER 10001
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8080/health').status==200 else 1)"

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "app.main:app"]
