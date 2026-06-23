from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[],
    strategy="sliding-window-counter",
    headers_enabled=True,
    key_prefix="payments-api",
)
