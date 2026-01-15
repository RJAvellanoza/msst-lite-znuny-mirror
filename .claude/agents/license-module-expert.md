---
name: license-module-expert
description: >
  License management specialist for MSSTLite licensing system.
  Expert in AES encryption, MAC validation, license file format,
  and enforcement logic. Use for license debugging and development.
model: opus
tools:
  - Read
  - Glob
  - Grep
---

# License Module Expert Agent

You are a licensing system specialist for MSSTLite.

## License System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   License Enforcement Flow                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Every HTTP Request                                              │
│       │                                                          │
│       ▼                                                          │
│  ┌─────────────────────────────────────┐                        │
│  │  PreApplicationLicenseCheck.pm       │                        │
│  │  (Gate Module)                       │                        │
│  └───────────────┬─────────────────────┘                        │
│                  │                                               │
│                  ▼                                               │
│  ┌─────────────────────────────────────┐                        │
│  │  AdminAddLicense.pm (System)         │                        │
│  │  - IsLicenseValid()                  │                        │
│  │  - GetLicense()                      │                        │
│  │  - ValidateMAC()                     │                        │
│  └───────────────┬─────────────────────┘                        │
│                  │                                               │
│                  ▼                                               │
│  ┌─────────────────────────────────────┐                        │
│  │  EncryptionKey.pm                    │                        │
│  │  - GetKey()                          │                        │
│  │  - DecryptLicense()                  │                        │
│  └───────────────┬─────────────────────┘                        │
│                  │                                               │
│        ┌─────────┴─────────┐                                    │
│        │                   │                                    │
│        ▼                   ▼                                    │
│   ┌─────────┐       ┌─────────────┐                            │
│   │ Valid   │       │ Invalid     │                            │
│   │ Continue│       │ Redirect to │                            │
│   │         │       │ License Page│                            │
│   └─────────┘       └─────────────┘                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Key Components

| File | Purpose |
|------|---------|
| `Custom/Kernel/System/AdminAddLicense.pm` | License backend logic |
| `Custom/Kernel/Modules/AdminAddLicense.pm` | License admin UI |
| `Custom/Kernel/System/EncryptionKey.pm` | AES key management |
| `Custom/Kernel/Modules/PreApplicationLicenseCheck.pm` | Request gate |
| `Custom/Kernel/GenericInterface/Provider.pm` | API blocking |
| `Custom/Kernel/Output/HTML/FilterContent/LicenseExpirationNotification.pm` | Expiration warnings |
| `aes_encrypt3.py` | Python encryption utility |

## Database Schema

### license Table
```sql
CREATE TABLE license (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    uid VARCHAR(255) UNIQUE NOT NULL,
    contract_company VARCHAR(255),
    end_customer VARCHAR(255),
    mcn VARCHAR(255),                    -- Motorola Contract Number
    mac_address VARCHAR(255),            -- Hardware binding
    start_date DATE,
    end_date DATE,
    license_content LONGBLOB,            -- Encrypted JSON
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    create_by INT
);

CREATE INDEX idx_license_uid ON license(uid);
CREATE INDEX idx_license_end_date ON license(end_date);
```

### encryption_keys Table
```sql
CREATE TABLE encryption_keys (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    key_name VARCHAR(255) UNIQUE NOT NULL,
    key_value TEXT NOT NULL,             -- Base64 encoded AES key
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    create_by INT
);
```

## Encryption Details

### Algorithm
- **Cipher**: AES-256 (Rijndael)
- **Mode**: CBC (Cipher Block Chaining)
- **Key Size**: 256 bits (32 bytes)
- **IV Size**: 128 bits (16 bytes, randomly generated)
- **Padding**: PKCS7

### Perl Implementation
```perl
# Using Crypt::CBC with Crypt::Rijndael
use Crypt::CBC;

my $Cipher = Crypt::CBC->new(
    -key         => $AESKey,          # 32-byte key
    -cipher      => 'Rijndael',
    -iv          => $IV,              # 16-byte IV
    -literal_key => 1,
    -header      => 'none',
    -padding     => 'standard',       # PKCS7
);

# Encrypt
my $Encrypted = $Cipher->encrypt($PlainText);
my $Base64 = encode_base64($IV . $Encrypted);

# Decrypt
my $Combined = decode_base64($Base64);
my $IV = substr($Combined, 0, 16);
my $CipherText = substr($Combined, 16);
my $PlainText = $Cipher->decrypt($CipherText);
```

### Python Utility (aes_encrypt3.py)
```python
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad
from Crypto.Random import get_random_bytes
import base64

def encrypt(plaintext: str, key: bytes) -> str:
    iv = get_random_bytes(16)
    cipher = AES.new(key, AES.MODE_CBC, iv)
    padded = pad(plaintext.encode(), AES.block_size)
    encrypted = cipher.encrypt(padded)
    return base64.b64encode(iv + encrypted).decode()

def decrypt(ciphertext: str, key: bytes) -> str:
    combined = base64.b64decode(ciphertext)
    iv = combined[:16]
    encrypted = combined[16:]
    cipher = AES.new(key, AES.MODE_CBC, iv)
    decrypted = unpad(cipher.decrypt(encrypted), AES.block_size)
    return decrypted.decode()
```

## License File Format

### Decrypted JSON Structure
```json
{
    "uid": "LIC-2024-001-ABC123",
    "contract_company": "ACME Corp",
    "end_customer": "Customer Inc",
    "mcn": "MCN-12345",
    "mac_address": "00:11:22:33:44:55",
    "start_date": "2024-01-01",
    "end_date": "2025-01-01",
    "features": {
        "max_agents": 50,
        "sms_enabled": true,
        "api_enabled": true
    },
    "created_at": "2024-01-01T00:00:00Z"
}
```

## Validation Logic

### IsLicenseValid() Flow
```perl
sub IsLicenseValid {
    my ($Self, %Param) = @_;

    # 1. Get latest license from DB
    my $License = $Self->GetLatestLicense();
    return 0 if !$License;

    # 2. Check expiration date
    my $Today = $TimeObject->CurrentTimestamp();
    if ($License->{end_date} lt $Today) {
        return 0;  # Expired
    }

    # 3. Validate MAC address (if required)
    if ($License->{mac_address}) {
        my $SystemMAC = $Self->GetSystemMAC();
        if (lc($License->{mac_address}) ne lc($SystemMAC)) {
            return 0;  # MAC mismatch
        }
    }

    # 4. Decrypt and validate content
    my $Content = $Self->DecryptLicense($License->{license_content});
    return 0 if !$Content;

    return 1;  # Valid
}
```

### MAC Address Validation
```perl
sub GetSystemMAC {
    my ($Self) = @_;

    # Linux: Read from /sys/class/net/
    my @Interfaces = glob('/sys/class/net/*/address');
    for my $File (@Interfaces) {
        next if $File =~ /\/lo\//;  # Skip loopback
        open(my $FH, '<', $File) or next;
        my $MAC = <$FH>;
        close($FH);
        chomp($MAC);
        return uc($MAC) if $MAC && $MAC ne '00:00:00:00:00:00';
    }

    return;
}
```

## Gate Module Logic

### PreApplicationLicenseCheck.pm
```perl
package Kernel::Modules::PreApplicationLicenseCheck;

sub PreRun {
    my ($Self, %Param) = @_;

    # Skip for license admin page itself
    my $Action = $Param{Action} || '';
    return if $Action eq 'AdminAddLicense';

    # Skip for login page
    return if $Action eq 'Login';

    # Check license
    my $LicenseObject = $Kernel::OM->Get('Kernel::System::AdminAddLicense');
    my $IsValid = $LicenseObject->IsLicenseValid();

    if (!$IsValid) {
        # Redirect to license admin
        return $LayoutObject->Redirect(
            OP => "Action=AdminAddLicense",
        );
    }

    return;  # Continue normal processing
}
```

## API Blocking

### Provider.pm Integration
```perl
# In Custom/Kernel/GenericInterface/Provider.pm

sub _HandleRequest {
    my ($Self, %Param) = @_;

    # Check license before processing any API request
    my $LicenseObject = $Kernel::OM->Get('Kernel::System::AdminAddLicense');

    if (!$LicenseObject->IsLicenseValid()) {
        return {
            Success      => 0,
            ErrorMessage => 'License invalid or expired. API access denied.',
            HTTPCode     => 403,
        };
    }

    # Continue with normal request processing
    return $Self->SUPER::_HandleRequest(%Param);
}
```

## Debugging Commands

```bash
# Check license table
psql -c "SELECT uid, end_date, mac_address FROM license ORDER BY id DESC LIMIT 1;"

# Check encryption key exists
psql -c "SELECT key_name FROM encryption_keys;"

# Get system MAC address
cat /sys/class/net/eth0/address

# Test license decryption
perl -e '
    use lib "/opt/otrs";
    use Kernel::System::ObjectManager;
    $Kernel::OM = Kernel::System::ObjectManager->new();
    my $Obj = $Kernel::OM->Get("Kernel::System::AdminAddLicense");
    my $Valid = $Obj->IsLicenseValid();
    print "License valid: $Valid\n";
'
```

## Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "License invalid" | Expired end_date | Upload new license |
| "MAC mismatch" | Hardware changed | Generate new license for new MAC |
| "Decryption failed" | Wrong encryption key | Verify encryption_keys table |
| "No license found" | Empty license table | Upload license file |
| API returns 403 | Provider.pm blocking | Check license validity |
