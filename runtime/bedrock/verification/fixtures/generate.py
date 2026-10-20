"""Regenerate owned signature fixtures; requires Python cryptography (development only).
The randomly generated private key lives only in memory. Production never trusts
this fixture key. Fixture payloads are recreated deterministically in Rust tests.
"""
from pathlib import Path
import hashlib
import struct
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives import hashes

root = Path(__file__).resolve().parent
key = rsa.generate_private_key(public_exponent=65537, key_size=4096)
public = key.public_key().public_numbers()
(root / 'test-key.public.bin').write_bytes(struct.pack('<6I', 0x31415352, 4096, 3, 512, 0, 0)
    + public.e.to_bytes(3, 'big') + public.n.to_bytes(512, 'big'))
for count in (2, 171):
    for encrypted in (False, True):
        leaf = bytearray(((count + 169) // 170) * 4096)
        for index in range(count):
            page = bytes((index * 17 + offset * 7) % 251 for offset in range(4096))
            offset = (index // 170) * 4096 + (index % 170) * 24
            length = 20 if encrypted else 24
            leaf[offset:offset + length] = hashlib.sha256(page).digest()[:length]
            if encrypted:
                leaf[offset + 20:offset + 24] = struct.pack('<I', index + 123)
        tree = bytes(leaf)
        if count > 170:
            parent = bytearray(4096)
            for i in range(len(leaf) // 4096):
                parent[i * 24:i * 24 + 24] = hashlib.sha256(leaf[i * 4096:(i + 1) * 4096]).digest()[:24]
            tree = bytes(parent) + tree
        header = bytearray(4096)
        header[0x200:0x208] = b'msft-xvd'
        struct.pack_into('<I', header, 0x208, 1 if encrypted else 3)
        struct.pack_into('<Q', header, 0x218, (count - 1) * 4096)
        struct.pack_into('<I', header, 0x28c, 4096)
        header[0x240:0x260] = hashlib.sha256(tree[:4096]).digest()
        header[:512] = key.sign(bytes(header[512:]), padding.PSS(mgf=padding.MGF1(hashes.SHA256()), salt_length=32), hashes.SHA256())
        (root / f'header-{count}-{int(encrypted)}.bin').write_bytes(header)
        if count == 2:
            header[0x470] = 1
            header[:512] = key.sign(bytes(header[512:]), padding.PSS(mgf=padding.MGF1(hashes.SHA256()), salt_length=32), hashes.SHA256())
            (root / f'header-{count}-{int(encrypted)}-mutable.bin').write_bytes(header)
print('Generated six public, owned signature fixtures; no private key saved.')
