class SSHCoreError(Exception): pass
class InvalidUsername(SSHCoreError): pass
class InvalidPassword(SSHCoreError): pass
class InvalidExpiry(SSHCoreError): pass
class AccountAlreadyExists(SSHCoreError): pass
class AccountNotFound(SSHCoreError): pass
class MetadataError(SSHCoreError): pass
class SystemCommandError(SSHCoreError): pass
