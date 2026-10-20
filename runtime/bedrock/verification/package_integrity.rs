//! macOS-native verification. No account data, external commands, or private keys.
use std::ffi::c_void;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

type Ref = *const c_void;
#[link(name = "CoreFoundation", kind = "framework")]
unsafe extern "C" {
    fn CFDataCreate(allocator: Ref, bytes: *const u8, len: isize) -> Ref;
    fn CFDictionaryCreate(allocator: Ref, keys: *const Ref, values: *const Ref,
                          count: isize, key_callbacks: Ref, value_callbacks: Ref) -> Ref;
    fn CFRelease(value: Ref);
}
#[link(name = "Security", kind = "framework")]
unsafe extern "C" {
    static kSecAttrKeyType: Ref;
    static kSecAttrKeyTypeRSA: Ref;
    static kSecAttrKeyClass: Ref;
    static kSecAttrKeyClassPublic: Ref;
    static kSecKeyAlgorithmRSASignatureMessagePSSSHA256: Ref;
    fn SecKeyCreateWithData(data: Ref, attributes: Ref, error: *mut Ref) -> Ref;
    fn SecKeyVerifySignature(key: Ref, algorithm: Ref, signed_data: Ref,
                             signature: Ref, error: *mut Ref) -> bool;
}
unsafe extern "C" { fn CC_SHA256(data: *const c_void, len: u32, digest: *mut u8) -> *mut u8; }

pub fn sha256(bytes: &[u8]) -> [u8; 32] {
    let mut digest = [0; 32];
    assert!(bytes.len() <= u32::MAX as usize);
    unsafe { CC_SHA256(bytes.as_ptr().cast(), bytes.len() as u32, digest.as_mut_ptr()); }
    digest
}

fn der(tag: u8, content: &[u8]) -> Vec<u8> {
    let mut out = vec![tag];
    if content.len() < 128 { out.push(content.len() as u8); }
    else { out.extend([0x82, (content.len() >> 8) as u8, content.len() as u8]); }
    out.extend(content); out
}

fn public_key_der(blob: &[u8]) -> Option<Vec<u8>> {
    if blob.len() != 539 || &blob[..4] != b"RSA1" { return None; }
    if u32::from_le_bytes(blob[4..8].try_into().ok()?) != 4096
        || u32::from_le_bytes(blob[8..12].try_into().ok()?) != 3
        || u32::from_le_bytes(blob[12..16].try_into().ok()?) != 512
        || blob[16..24].iter().any(|b| *b != 0) { return None; }
    let mut modulus = vec![0]; modulus.extend(&blob[27..]);
    let mut parts = der(2, &modulus); parts.extend(der(2, &blob[24..27]));
    Some(der(0x30, &parts))
}

struct Owned(Ref);
impl Drop for Owned { fn drop(&mut self) { if !self.0.is_null() { unsafe { CFRelease(self.0); } } } }

fn verify_with(blob: &[u8], signature: &[u8], message: &[u8]) -> bool {
    let Some(der) = public_key_der(blob) else { return false; };
    unsafe {
        let data = Owned(CFDataCreate(std::ptr::null(), der.as_ptr(), der.len() as isize));
        let keys = [kSecAttrKeyType, kSecAttrKeyClass];
        let values = [kSecAttrKeyTypeRSA, kSecAttrKeyClassPublic];
        let attributes = Owned(CFDictionaryCreate(std::ptr::null(), keys.as_ptr(), values.as_ptr(),
                                                2, std::ptr::null(), std::ptr::null()));
        let mut error: Ref = std::ptr::null();
        let key = Owned(SecKeyCreateWithData(data.0, attributes.0, &mut error));
        let _error = Owned(error);
        if key.0.is_null() { return false; }
        let bytes = Owned(CFDataCreate(std::ptr::null(), message.as_ptr(), message.len() as isize));
        let sig = Owned(CFDataCreate(std::ptr::null(), signature.as_ptr(), signature.len() as isize));
        let mut error: Ref = std::ptr::null();
        let valid = SecKeyVerifySignature(key.0, kSecKeyAlgorithmRSASignatureMessagePSSSHA256,
                                         bytes.0, sig.0, &mut error);
        let _error = Owned(error);
        valid
    }
}

/// Return only a signature-verified header length. No format parser consumes
/// network-supplied offsets before this check. Both known header envelopes
/// cover all fields used by the pinned XVD parser, including the root hash.
pub fn verify_header(bytes: &[u8]) -> Option<usize> {
    verify_header_with(bytes, &[include_bytes!("GreenGamesPublicKey.public.bin"), include_bytes!("GreenXvdPublicKey.public.bin")])
}

fn verify_header_with(bytes: &[u8], keys: &[&[u8]]) -> Option<usize> {
    for length in [0x1000, 0x3000] {
        if bytes.len() < length { continue; }
        for key in keys {
            if verify_with(key, &bytes[..0x200], &bytes[0x200..length]) {
                return Some(length);
            }
        }
    }
    None
}

const PAGE: u64 = 4096;
const ENTRIES: u64 = 170;
const MAX_PACKAGE: u64 = 32 * 1024 * 1024 * 1024;

/// Offsets are accepted only from a signature-verified fixed-layout header.
/// Unsupported variants fail closed. The signed mutable-page count skips an
/// unused section; the pinned parser never reads its contents.
pub struct SignedLayout {
    pub tree_start: u64,
    pub data_start: u64,
    pub metadata_end: u64,
    pages: u64,
    levels: Vec<(u64, u64)>, // relative starting page/count, top first
    root: [u8; 32],
    leaf_hash_bytes: usize,
}

fn layout(bytes: &[u8], file_size: u64) -> Result<SignedLayout, &'static str> {
    if bytes.len() < 4096 || &bytes[0x200..0x208] != b"msft-xvd" { return Err("package_format"); }
    let u32_at = |n| u32::from_le_bytes(bytes[n..n + 4].try_into().unwrap()) as u64;
    let u64_at = |n| u64::from_le_bytes(bytes[n..n + 8].try_into().unwrap());
    let flags = u32_at(0x208);
    // The current parser does not authenticate resiliency/dynamic layouts.
    if flags & (4 | 16) != 0 || u32_at(0x280) != 0 || u32_at(0x288) != 0 {
        return Err("package_integrity_format");
    }
    let user = u32_at(0x28c).div_ceil(PAGE);
    let xvc = u32_at(0x290).div_ceil(PAGE);
    let dynamic = u32_at(0x294).div_ceil(PAGE);
    let drive = u64_at(0x218).div_ceil(PAGE);
    let pages = user.checked_add(xvc).and_then(|n| n.checked_add(dynamic)).and_then(|n| n.checked_add(drive))
        .ok_or("package_size")?;
    if file_size > MAX_PACKAGE || pages == 0 || pages > MAX_PACKAGE / PAGE { return Err("package_size"); }
    let mut counts = vec![pages.div_ceil(ENTRIES)];
    while *counts.last().unwrap() > 1 { counts.push(counts.last().unwrap().div_ceil(ENTRIES)); }
    if counts.len() > 4 { return Err("package_integrity_format"); }
    counts.reverse();
    let mut next = 0;
    let levels = counts.into_iter().map(|count| { let start = next; next += count; (start, count) }).collect();
    let tree_start = PAGE * (3 + bytes[0x470] as u64);
    let data_start = tree_start + next * PAGE;
    let end = data_start.checked_add(pages * PAGE).ok_or("package_size")?;
    if end != file_size { return Err("package_size"); }
    let root = bytes[0x240..0x260].try_into().unwrap();
    if root == [0; 32] { return Err("package_integrity"); }
    Ok(SignedLayout { tree_start, data_start, metadata_end: data_start + (user + xvc + dynamic) * PAGE,
                      pages, levels, root, leaf_hash_bytes: if flags & 2 == 0 { 20 } else { 24 } })
}

pub fn signed_layout(bytes: &[u8], file_size: u64) -> Result<SignedLayout, &'static str> {
    verify_header(bytes).ok_or("package_signature")?;
    layout(bytes, file_size)
}

fn verify_tree(tree: &[u8], layout: &SignedLayout) -> Result<(), &'static str> {
    let tree_bytes = layout.data_start - layout.tree_start;
    if tree.len() as u64 != tree_bytes || tree.len() < 4096 || sha256(&tree[..4096]) != layout.root {
        return Err("package_integrity");
    }
    for pair in layout.levels.windows(2) {
        let (parent, parent_count) = pair[0];
        let (child, child_count) = pair[1];
        if child_count.div_ceil(ENTRIES) != parent_count { return Err("package_integrity_format"); }
        for index in 0..child_count {
            let entry = ((parent + index / ENTRIES) * PAGE + (index % ENTRIES) * 24) as usize;
            let block = ((child + index) * PAGE) as usize;
            if sha256(&tree[block..block + 4096])[..24] != tree[entry..entry + 24] {
                return Err("package_integrity");
            }
        }
    }
    Ok(())
}

/// The complete archive is checked before its package/file parsers run. The
/// signed root anchors every tree page and every encrypted/unencrypted data
/// page; no later network read can replace the verified local bytes.
pub fn verify_archive(path: &Path) -> Result<SignedLayout, &'static str> {
    verify_archive_with(path, &[include_bytes!("GreenGamesPublicKey.public.bin"), include_bytes!("GreenXvdPublicKey.public.bin")])
}

fn verify_archive_with(path: &Path, keys: &[&[u8]]) -> Result<SignedLayout, &'static str> {
    let mut file = std::fs::File::open(path).map_err(|_| "package_cache")?;
    let size = file.metadata().map_err(|_| "package_cache")?.len();
    let mut header = [0; 12288];
    file.read_exact(&mut header).map_err(|_| "package_size")?;
    verify_header_with(&header, keys).ok_or("package_signature")?;
    let layout = layout(&header, size)?;
    let mut tree = vec![0; (layout.data_start - layout.tree_start) as usize];
    file.seek(SeekFrom::Start(layout.tree_start)).map_err(|_| "package_cache")?;
    file.read_exact(&mut tree).map_err(|_| "package_size")?;
    verify_tree(&tree, &layout)?;
    let leaf = layout.levels.last().ok_or("package_integrity_format")?.0;
    let mut page = [0; 4096];
    for index in 0..layout.pages {
        file.read_exact(&mut page).map_err(|_| "package_size")?;
        let entry = ((leaf + index / ENTRIES) * PAGE + index % ENTRIES * 24) as usize;
        if sha256(&page)[..layout.leaf_hash_bytes] != tree[entry..entry + layout.leaf_hash_bytes] {
            return Err("package_integrity");
        }
    }
    Ok(layout)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn trusted_public_keys_and_malformed_headers() {
        assert_eq!(format!("{:x}", u64::from_be_bytes(sha256(b"abc")[..8].try_into().unwrap())), "ba7816bf8f01cfea");
        for key in [include_bytes!("GreenGamesPublicKey.public.bin"), include_bytes!("GreenXvdPublicKey.public.bin")] {
            assert!(public_key_der(key).is_some());
            assert!(!verify_with(key, &[0; 512], &[0; 3584]));
        }
        assert!(verify_header(&[]).is_none());
        assert!(verify_header(&[0; 0x3000]).is_none());
        assert!(public_key_der(b"RSA1").is_none());
    }
}

#[cfg(test)]
mod archive_tests {
    use super::*;
    use std::io::Write;
    const KEY: &[u8] = include_bytes!("fixtures/test-key.public.bin");
    fn fixture(count: usize, encrypted: bool) -> Vec<u8> { fixture_with_mutable(count, encrypted, false) }
    fn fixture_with_mutable(count: usize, encrypted: bool, mutable: bool) -> Vec<u8> {
        let header: &[u8] = match (count, encrypted, mutable) {
            (2, false, false) => include_bytes!("fixtures/header-2-0.bin"),
            (2, true, false) => include_bytes!("fixtures/header-2-1.bin"),
            (171, false, false) => include_bytes!("fixtures/header-171-0.bin"),
            (171, true, false) => include_bytes!("fixtures/header-171-1.bin"),
            (2, false, true) => include_bytes!("fixtures/header-2-0-mutable.bin"),
            (2, true, true) => include_bytes!("fixtures/header-2-1-mutable.bin"),
            _ => panic!("unknown fixture"),
        };
        let mut data = Vec::new();
        let mut leaf = vec![0; count.div_ceil(170) * 4096];
        for index in 0..count {
            let page: Vec<u8> = (0..4096).map(|offset| ((index * 17 + offset * 7) % 251) as u8).collect();
            let entry = index / 170 * 4096 + index % 170 * 24;
            let length = if encrypted {20} else {24};
            leaf[entry..entry + length].copy_from_slice(&sha256(&page)[..length]);
            if encrypted { leaf[entry + 20..entry + 24].copy_from_slice(&((index + 123) as u32).to_le_bytes()); }
            data.extend(page);
        }
        let mut archive = header.to_vec(); archive.resize(if mutable { 16384 } else {12288}, 0);
        if count > 170 {
            let mut parent = vec![0; 4096];
            for (index, page) in leaf.chunks_exact(4096).enumerate() {
                parent[index * 24..index * 24 + 24].copy_from_slice(&sha256(page)[..24]);
            }
            archive.extend(parent);
        }
        archive.extend(leaf); archive.extend(data); archive
    }
    fn check(bytes: &[u8]) -> Result<SignedLayout, &'static str> {
        let mut temporary = tempfile::NamedTempFile::new().unwrap();
        temporary.write_all(bytes).unwrap(); temporary.flush().unwrap();
        verify_archive_with(temporary.path(), &[KEY])
    }
    #[test]
    fn accepts_owned_signed_archives_and_never_trusts_fixture_key_in_production() {
        for count in [2, 171] { for encrypted in [false, true] {
            let bytes = fixture(count, encrypted);
            let layout = check(&bytes).unwrap();
            assert_eq!(layout.pages, count as u64);
            assert_eq!(layout.metadata_end, layout.data_start + 4096);
            assert!(verify_header(&bytes[..12288]).is_none());
        }}
    }
    #[test]
    fn rejects_changed_signature_header_tree_metadata_first_and_last_data_page() {
        for encrypted in [false, true] {
            let bytes = fixture(171, encrypted);
            let start = check(&bytes).unwrap().data_start as usize;
            for offset in [0, 0x240, 0x28c, 12288, 16384, 20480, start, start + 4096, bytes.len() - 1] {
                let mut corrupt = bytes.clone(); corrupt[offset] ^= 1;
                assert!(check(&corrupt).is_err(), "accepted corruption at {offset}");
            }
            let mut truncated = bytes.clone(); truncated.pop();
            assert_eq!(check(&truncated).err(), Some("package_size"));
            let mut extended = bytes.clone(); extended.push(0);
            assert_eq!(check(&extended).err(), Some("package_size"));
        }
    }
    #[test]
    fn signed_mutable_count_skips_unused_bytes_without_weakening_data_checks() {
        for encrypted in [false, true] {
            let mut bytes = fixture_with_mutable(2, encrypted, true);
            bytes[12288..16384].fill(0x81); // The pinned parser never consumes this section.
            let result = check(&bytes).unwrap();
            assert_eq!(result.tree_start, 16384);
            bytes[result.data_start as usize] ^= 1;
            assert_eq!(check(&bytes).err(), Some("package_integrity"));
        }
    }
    #[test]
    fn unsupported_layouts_fail_closed_even_before_tree_parsing() {
        let bytes = fixture(2, false);
        for (offset, value) in [(0x208, 7), (0x208, 19), (0x280, 1), (0x288, 1)] {
            let mut header = bytes.clone(); header[offset] = value;
            assert_eq!(layout(&header, bytes.len() as u64).err(), Some("package_integrity_format"));
        }
        assert_eq!(layout(&bytes, MAX_PACKAGE + 4096).err(), Some("package_size"));
    }
}
