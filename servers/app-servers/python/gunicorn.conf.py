# Health-InfraOps Gunicorn Configuration

import multiprocessing
import os

# Server socket
bind = "0.0.0.0:8000"
backlog = 2048

# Worker processes
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "gevent"
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 50
timeout = 30
keepalive = 2

# Security
limit_request_line = 4096
limit_request_fields = 100
limit_request_field_size = 8190

# Process naming
proc_name = "infokes-api"

# Logging
accesslog = "/var/log/gunicorn/access.log"
errorlog = "/var/log/gunicorn/error.log"
loglevel = "info"
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s"'

# Server mechanics
daemon = False
pidfile = "/var/run/gunicorn/gunicorn.pid"
umask = 0
user = None
group = None
tmp_upload_dir = None

# SSL (if needed)
# keyfile = "/etc/ssl/private/infokes.key"
# certfile = "/etc/ssl/certs/infokes.crt"

# Preload app
preload_app = True

# Worker temp directory
worker_tmp_dir = "/dev/shm"

# Environment variables
raw_env = [
    "PYTHONPATH=/opt/infokes/app",
    "INFOKES_ENV=production",
]

# Custom settings
def when_ready(server):
    server.log.info("Infokes API server is ready and accepting connections")

def pre_fork(server, worker):
    pass

def post_fork(server, worker):
    server.log.info(f"Worker {worker.pid} spawned")

def pre_exec(server):
    server.log.info("Forked child, re-executing")

def worker_int(worker):
    worker.log.info("Worker received INT or QUIT signal")

def worker_abort(worker):
    worker.log.info("Worker received SIGABRT signal")

def pre_request(worker, req):
    worker.log.debug(f"Request: {req.method} {req.path}")

def post_request(worker, req, environ, resp):
    worker.log.debug(f"Response: {resp.status}")