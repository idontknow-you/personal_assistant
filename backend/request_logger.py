"""Request logging middleware for audit trail.

Logs every API request with timestamp, method, path, status, and user ID.
Logs are written to stdout (captured by Render's log drain).
"""

import time
import logging
from flask import request, g

logger = logging.getLogger("personal_os")


def init_request_logger(app):
    """Register before/after request hooks for logging."""

    @app.before_request
    def _start_timer():
        g._request_start = time.time()

    @app.after_request
    def _log_request(response):
        duration_ms = (time.time() - getattr(g, "_request_start", time.time())) * 1000

        # Extract user ID if available
        user_id = "anonymous"
        if hasattr(g, "user") and g.user:
            user_id = g.user.get("uid", "unknown")

        # Skip health checks to reduce noise
        if request.path == "/api/health":
            return response

        log_line = (
            f"{request.method} {request.path} "
            f"status={response.status_code} "
            f"user={user_id} "
            f"duration={duration_ms:.0f}ms "
            f"ip={request.remote_addr}"
        )

        if response.status_code >= 500:
            logger.error(log_line)
        elif response.status_code >= 400:
            logger.warning(log_line)
        else:
            logger.info(log_line)

        return response
