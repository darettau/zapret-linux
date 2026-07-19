import logging
import os
import socket as _socket

from dataclasses import dataclass, field
from typing import Dict, List

from .balancer import balancer

log = logging.getLogger('tg-mtproto-proxy')

_CFPROXY_ENC: List[str] = [
    'virkgj.com', 
    'vmmzovy.com', 
    'mkuosckvso.com', 
    'zaewayzmplad.com', 
    'twdmbzcm.com',
    'awzwsldi.com',
    'clngqrflngqin.com',
    'tjacxbqtj.com',
    'bxaxtxmrw.com',
    'dmohrsgmohcrwb.com',
    'vwbmtmoi.com',
    'khgrre.com',
    'ulihssf.com',
    'tmhqsdqmfpmk.com',
    'xwuwoqbm.com',
    'orgcnunpj.com',
    'zhkuldz.com',
    'zypoljnslxa.com',
    'efabnxaowuzs.com',
    'zaftuzsftqdq.com'
]
_S = ''.join(chr(c) for c in (46, 99, 111, 46, 117, 107))


def _dd(s: str) -> str:
    """Only for decoding CF proxy domains"""
    if not s[-4:] == '.com':
        return s
    p, n = s[:-4], sum(c.isalpha() for c in s[:-4])
    return ''.join(
        chr((ord(c) - (97 if c > '`' else 65) - n) % 26 + (97 if c > '`' else 65))
        if c.isalpha() else c for c in p
    ) + _S


CFPROXY_DEFAULT_DOMAINS: List[str] = [_dd(d) for d in _CFPROXY_ENC]


@dataclass
class ProxyConfig:
    port: int = 1443
    host: str = '127.0.0.1'
    secret: str = field(default_factory=lambda: os.urandom(16).hex())
    dc_redirects: Dict[int, str] = field(default_factory=lambda: {2: '149.154.167.220', 4: '149.154.167.220'})
    buffer_size: int = 256 * 1024
    pool_size: int = 4
    fallback_cfproxy: bool = True
    cfproxy_user_domains: List[str] = field(default_factory=list)
    cfproxy_worker_domains: List[str] = field(default_factory=list)
    fake_tls_domain: str = ''
    proxy_protocol: bool = False


proxy_config = ProxyConfig()


def coerce_domain_list(value) -> List[str]:
    if isinstance(value, str):
        items = value.replace(',', ' ').replace(';', ' ').split()
    elif isinstance(value, (list, tuple)):
        items: List[str] = []
        for entry in value:
            if isinstance(entry, str):
                items.extend(entry.replace(',', ' ').replace(';', ' ').split())
    else:
        return []
    seen = set()
    result: List[str] = []
    for item in items:
        item = item.strip()
        if not item:
            continue
        key = item.lower()
        if key in seen:
            continue
        seen.add(key)
        result.append(item)
    return result


def init_cfproxy_domains() -> None:
    if proxy_config.cfproxy_user_domains:
        return
    balancer.update_domains_list(CFPROXY_DEFAULT_DOMAINS)


def parse_dc_ip_list(dc_ip_list: List[str]) -> Dict[int, str]:
    dc_redirects: Dict[int, str] = {}
    for entry in dc_ip_list:
        if ':' not in entry:
            err = ValueError(
                f"Invalid --dc-ip format {entry!r}, expected DC:IP")
            err.entry = entry
            err.kind = "format"
            raise err
        dc_s, ip_s = entry.split(':', 1)
        try:
            dc_n = int(dc_s)
            _socket.inet_aton(ip_s)
        except (ValueError, OSError):
            err = ValueError(f"Invalid --dc-ip {entry!r}")
            err.entry = entry
            err.kind = "invalid"
            raise err
        dc_redirects[dc_n] = ip_s
    return dc_redirects
