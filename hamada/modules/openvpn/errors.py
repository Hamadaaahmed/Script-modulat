"""OpenVPN Core errors."""


class OpenVPNCoreError(Exception):
    pass


class OpenVPNConfigError(OpenVPNCoreError):
    pass


class OpenVPNSystemError(OpenVPNCoreError):
    pass
