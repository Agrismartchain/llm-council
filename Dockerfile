# Stage 1 - Build frontend
FROM node:20-slim AS frontend-build
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm install
COPY frontend/ ./
RUN npm run build

# Stage 2 - Python backend + nginx
FROM python:3.11-slim
WORKDIR /app

# Install nginx + supervisor
RUN apt-get update && apt-get install -y nginx supervisor && rm -rf /var/lib/apt/lists/*

# Install uv
RUN pip install uv

# Install Python deps
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

# Copy backend
COPY backend/ ./backend/

# Copy built frontend to nginx
COPY --from=frontend-build /app/frontend/dist /var/www/html

# Nginx config
RUN cat > /etc/nginx/sites-available/default << 'NGINX'
server {
    listen 80;
    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://localhost:8001/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINX

# Supervisor config
RUN cat > /etc/supervisor/conf.d/llm-council.conf << 'SUPERVISOR'
[supervisord]
nodaemon=true

[program:backend]
command=uv run python -m backend.main
directory=/app
autostart=true
autorestart=true

[program:nginx]
command=nginx -g "daemon off;"
autostart=true
autorestart=true
SUPERVISOR

EXPOSE 80
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
