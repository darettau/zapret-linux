from .config import parse_dc_ip_list, proxy_config, coerce_domain_list
from .utils import get_link_host

__version__ = "1.0"

__all__ = ["__version__", "get_link_host", "proxy_config", "parse_dc_ip_list", "coerce_domain_list"]
