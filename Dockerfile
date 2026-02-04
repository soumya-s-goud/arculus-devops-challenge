# Multi-stage Dockerfile - builder + runtime
FROM python:3.9-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install minimal build deps needed for some wheels and psycopg2 if required
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Copy only requirements first for efficient caching
COPY requirements.txt ./

# Install dependencies into a /install prefix to copy into runtime
RUN python -m pip install --upgrade pip \
    && pip install --prefix=/install -r requirements.txt \
    && pip install --prefix=/install gunicorn

# ---- Runtime image ----
FROM python:3.9-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/usr/local/bin:$PATH

# Create an unprivileged user
RUN useradd --create-home --shell /bin/bash appuser \
    && mkdir /app \
    && chown appuser:appuser /app

WORKDIR /app

# Copy installed Python packages from builder
COPY --from=builder /install /usr/local

# Copy application source (respect .dockerignore)
COPY . /app

# Ensure non-root ownership of app files
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

EXPOSE 8000

# Run the app with Gunicorn. Assumes the Flask app is exposed as `app` in apps/main.py
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8000", "apps.main:app"]