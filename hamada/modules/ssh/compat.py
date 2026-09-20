"""Compatibility helpers used by selectively migrated public commands."""
from .accounts import SSHAccountService

def renew(username: str, days: int, service=None):
    return (service or SSHAccountService()).renew_account(username, days)

def delete(username: str, service=None):
    return (service or SSHAccountService()).delete_account(username)
