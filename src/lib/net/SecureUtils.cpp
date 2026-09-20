/*
    barrier -- mouse and keyboard sharing utility
    Copyright (C) Barrier contributors

    This package is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    found in the file LICENSE that should have accompanied this file.

    This package is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

    -----------------------------------------------------------------------
    create_fingerprint_randomart() has been taken from the OpenSSH project.
    Copyright information follows.

    Copyright (c) 2000, 2001 Markus Friedl.  All rights reserved.
    Copyright (c) 2008 Alexander von Gernler.  All rights reserved.
    Copyright (c) 2010,2011 Damien Miller.  All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:
    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
    IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
    OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
    IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
    NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
    THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include "SecureUtils.h"
#include "FingerprintDatabase.h"
#include "base/String.h"
#include "base/Log.h"
#include "base/finally.h"
#include "common/DataDirectories.h"
#include "io/filesystem.h"

#include <openssl/evp.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/pem.h>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <mutex>
#include <system_error>

#if !SYSAPI_WIN32
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

#if SYSAPI_WIN32
// Windows builds require a shim that makes it possible to link to different
// versions of the Win32 C runtime. See OpenSSL FAQ.
#include <openssl/applink.c>
#endif

namespace barrier {

namespace {

const EVP_MD* get_digest_for_type(FingerprintType type)
{
    switch (type) {
        case FingerprintType::SHA1: return EVP_sha1();
        case FingerprintType::SHA256: return EVP_sha256();
    }
    throw std::runtime_error("Unknown fingerprint type " + std::to_string(static_cast<int>(type)));
}

// Opens a file that only the owner can read, creating it that way before anything is written
// into it. A plain fopen() creates a world-readable file, which would hand the unencrypted
// private key to every local user for as long as it takes to write the next line.
std::FILE* fopen_owner_only_path(const fs::path& path)
{
#if SYSAPI_WIN32
    // TODO: the Windows equivalent is an explicit DACL granting access to the current user
    // only, applied with SetNamedSecurityInfo(path, SE_FILE_OBJECT,
    // DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, ...) on the created
    // file. Until that is written the key file inherits the directory ACL and may be readable
    // by other local users.
    return fopen_utf8_path(path, "w");
#else
    int fd = ::open(path.native().c_str(), O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR);
    if (fd == -1) {
        return nullptr;
    }

    // O_CREAT ignores the mode when the file already exists, so a certificate left behind by
    // an older version must be narrowed explicitly.
    if (::fchmod(fd, S_IRUSR | S_IWUSR) == -1) {
        ::close(fd);
        return nullptr;
    }

    auto* fp = ::fdopen(fd, "w");
    if (!fp) {
        ::close(fd);
    }
    return fp;
#endif
}

// Best effort: the key file itself is already owner-only, this only stops other users from
// listing and traversing the directory that holds it.
void restrict_directory_to_owner(const fs::path& path)
{
    std::error_code ec;
    fs::permissions(path, fs::perms::owner_all, fs::perm_options::replace, ec);
}

} // namespace

std::string format_ssl_fingerprint(const std::vector<uint8_t>& fingerprint, bool separator)
{
    std::string result = barrier::string::to_hex(fingerprint, 2);

    // all uppercase
    barrier::string::uppercase(result);

    if (separator) {
        // add colon to separate each 2 characters
        size_t separators = result.size() / 2;
        for (size_t i = 1; i < separators; i++) {
            result.insert(i * 3 - 1, ":");
        }
    }
    return result;
}

std::string format_ssl_fingerprint_columns(const std::vector<uint8_t>& fingerprint)
{
    auto max_columns = 8;

    std::string hex = barrier::string::to_hex(fingerprint, 2);
    barrier::string::uppercase(hex);
    if (hex.empty() || hex.size() % 2 != 0) {
        return hex;
    }

    std::string separated;
    for (std::size_t i = 0; i < hex.size(); i += max_columns * 2) {
        for (std::size_t j = i; j < i + 16 && j < hex.size() - 1; j += 2) {
            separated.push_back(hex[j]);
            separated.push_back(hex[j + 1]);
            separated.push_back(':');
        }
        separated.push_back('\n');
    }
    separated.pop_back(); // we don't need last newline character
    return separated;
}

FingerprintData get_ssl_cert_fingerprint(X509* cert, FingerprintType type)
{
    if (!cert) {
        throw std::runtime_error("certificate is null");
    }

    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digest_length = 0;
    int result = X509_digest(cert, get_digest_for_type(type), digest, &digest_length);

    if (result <= 0) {
        throw std::runtime_error("failed to calculate fingerprint, digest result: " +
                                 std::to_string(result));
    }

    std::vector<std::uint8_t> digest_vec;
    digest_vec.assign(reinterpret_cast<std::uint8_t*>(digest),
                      reinterpret_cast<std::uint8_t*>(digest) + digest_length);
    return {fingerprint_type_to_string(type), digest_vec};
}

FingerprintData get_pem_file_cert_fingerprint(const std::string& path, FingerprintType type)
{
    auto fp = fopen_utf8_path(path, "r");
    if (!fp) {
        throw std::runtime_error("Could not open certificate path");
    }
    auto file_close = finally([fp]() { std::fclose(fp); });

    X509* cert = PEM_read_X509(fp, nullptr, nullptr, nullptr);
    if (!cert) {
        throw std::runtime_error("Certificate could not be parsed");
    }
    auto cert_free = finally([cert]() { X509_free(cert); });

    return get_ssl_cert_fingerprint(cert, type);
}

void generate_pem_self_signed_cert(const std::string& path)
{
    // Trust in this protocol is pinned to the certificate fingerprint, not to
    // X.509 validity, so expiry buys almost nothing here -- but it does force
    // the fingerprint to change, which silently breaks the link until the user
    // re-approves the peer. A long lifetime keeps the expiry check meaningful
    // for genuinely stale keys without breaking a working setup every year.
    auto expiration_days = 3650;

    auto* private_key = EVP_RSA_gen(2048);
    if (!private_key) {
        throw std::runtime_error("Failed to generate RSA key");
    }
    auto private_key_free = finally([private_key](){ EVP_PKEY_free(private_key); });

    auto* cert = X509_new();
    if (!cert) {
        throw std::runtime_error("Could not allocate certificate");
    }
    auto cert_free = finally([cert]() { X509_free(cert); });

    ASN1_INTEGER_set(X509_get_serialNumber(cert), 1);
    X509_gmtime_adj(X509_get_notBefore(cert), 0);
    X509_gmtime_adj(X509_get_notAfter(cert), expiration_days * 24 * 3600);
    X509_set_pubkey(cert, private_key);

    // Build the name separately rather than mutating the one owned by the
    // certificate: OpenSSL 4.x returns a const X509_NAME* from
    // X509_get_subject_name, 3.x does not, and both set_* calls copy it.
    auto* name = X509_NAME_new();
    if (!name) {
        throw std::runtime_error("failed to allocate certificate subject name");
    }
    auto name_free = finally([name]() { X509_NAME_free(name); });

    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,
                               reinterpret_cast<const unsigned char *>("Barrier"), -1, -1, 0);
    X509_set_subject_name(cert, name);
    X509_set_issuer_name(cert, name);

    X509_sign(cert, private_key, EVP_sha256());

    auto cert_path = fs::u8path(path);

    // the unencrypted private key shares this file with the certificate
    restrict_directory_to_owner(cert_path.parent_path());

    auto fp = fopen_owner_only_path(cert_path);
    if (!fp) {
        throw std::runtime_error("Could not open certificate output path");
    }
    auto file_close = finally([fp]() { std::fclose(fp); });

    PEM_write_PrivateKey(fp, private_key, nullptr, nullptr, 0, nullptr, nullptr);
    PEM_write_X509(fp, cert);
}

/*
    Draw an ASCII-Art representing the fingerprint so human brain can
    profit from its built-in pattern recognition ability.
    This technique is called "random art" and can be found in some
    scientific publications like this original paper:

    "Hash Visualization: a New Technique to improve Real-World Security",
    Perrig A. and Song D., 1999, International Workshop on Cryptographic
    Techniques and E-Commerce (CrypTEC '99)
    sparrow.ece.cmu.edu/~adrian/projects/validation/validation.pdf

    The subject came up in a talk by Dan Kaminsky, too.

    If you see the picture is different, the key is different.
    If the picture looks the same, you still know nothing.

    The algorithm used here is a worm crawling over a discrete plane,
    leaving a trace (augmenting the field) everywhere it goes.
    Movement is taken from dgst_raw 2bit-wise.  Bumping into walls
    makes the respective movement vector be ignored for this turn.
    Graphs are not unambiguous, because circles in graphs can be
walked in either direction.
 */

/*
    Field sizes for the random art.  Have to be odd, so the starting point
    can be in the exact middle of the picture, and FLDBASE should be >=8 .
    Else pictures would be too dense, and drawing the frame would
    fail, too, because the key type would not fit in anymore.
*/
#define	FLDBASE		8
#define	FLDSIZE_Y	(FLDBASE + 1)
#define	FLDSIZE_X	(FLDBASE * 2 + 1)

std::string create_fingerprint_randomart(const std::vector<std::uint8_t>& dgst_raw)
{
    /*
     * Chars to be used after each other every time the worm
     * intersects with itself.  Matter of taste.
     */
    const char* augmentation_string = " .o+=*BOX@%&#/^SE";
    char *p;
    std::uint8_t field[FLDSIZE_X][FLDSIZE_Y];
    std::size_t i;
    std::uint32_t b;
    int	 x, y;
    std::size_t len = strlen(augmentation_string) - 1;

    std::vector<char> retval;
    retval.reserve((FLDSIZE_X + 3) * (FLDSIZE_Y + 2));

    auto add_char = [&retval](char ch) { retval.push_back(ch); };

    /* initialize field */
    std::memset(field, 0, FLDSIZE_X * FLDSIZE_Y * sizeof(char));
    x = FLDSIZE_X / 2;
    y = FLDSIZE_Y / 2;

    /* process raw key */
    for (i = 0; i < dgst_raw.size(); i++) {
        /* each byte conveys four 2-bit move commands */
        int input = dgst_raw[i];
        for (b = 0; b < 4; b++) {
            /* evaluate 2 bit, rest is shifted later */
            x += (input & 0x1) ? 1 : -1;
            y += (input & 0x2) ? 1 : -1;

            /* assure we are still in bounds */
            x = std::max(x, 0);
            y = std::max(y, 0);
            x = std::min(x, FLDSIZE_X - 1);
            y = std::min(y, FLDSIZE_Y - 1);

            /* augment the field */
            if (field[x][y] < len - 2)
                field[x][y]++;
            input = input >> 2;
        }
    }

    /* mark starting point and end point*/
    field[FLDSIZE_X / 2][FLDSIZE_Y / 2] = len - 1;
    field[x][y] = len;

    /* output upper border */
    add_char('+');
    for (i = 0; i < FLDSIZE_X; i++)
        add_char('-');
    add_char('+');
    add_char('\n');

    /* output content */
    for (y = 0; y < FLDSIZE_Y; y++) {
        add_char('|');
        for (x = 0; x < FLDSIZE_X; x++)
            add_char(augmentation_string[std::min<int>(field[x][y], len)]);
        add_char('|');
        add_char('\n');
    }

    /* output lower border */
    add_char('+');
    for (i = 0; i < FLDSIZE_X; i++)
        add_char('-');
    add_char('+');

    return std::string{retval.data(), retval.size()};
}

static void ensure_local_certificate_once();

bool is_certificate_valid(const std::string& path)
{
    auto fp = fopen_utf8_path(path, "r");
    if (!fp) {
        return false;
    }
    auto file_close = finally([fp]() { std::fclose(fp); });

    auto* cert = PEM_read_X509(fp, nullptr, nullptr, nullptr);
    if (!cert) {
        LOG((CLOG_WARN "could not read certificate from %s", path.c_str()));
        return false;
    }
    auto cert_free = finally([cert]() { X509_free(cert); });

    auto* pubkey = X509_get_pubkey(cert);
    if (!pubkey) {
        LOG((CLOG_WARN "certificate %s has no public key", path.c_str()));
        return false;
    }
    auto pubkey_free = finally([pubkey]() { EVP_PKEY_free(pubkey); });

    auto key_type = EVP_PKEY_base_id(pubkey);
    if (key_type != EVP_PKEY_RSA && key_type != EVP_PKEY_DSA) {
        LOG((CLOG_WARN "certificate %s uses an unsupported key type", path.c_str()));
        return false;
    }

    if (EVP_PKEY_bits(pubkey) < 2048) {
        LOG((CLOG_WARN "certificate %s key is shorter than 2048 bits", path.c_str()));
        return false;
    }

    // The old GUI never looked at this, so a certificate was reused forever and
    // its stated 365-day lifetime meant nothing.
    if (X509_cmp_current_time(X509_get0_notAfter(cert)) <= 0) {
        LOG((CLOG_NOTE "certificate %s has expired", path.c_str()));
        return false;
    }

    return true;
}

void ensure_local_certificate()
{
    // Cheap to call from every connection attempt; the work happens once.
    static std::once_flag once;
    std::call_once(once, []() { ensure_local_certificate_once(); });
}

static void ensure_local_certificate_once()
{
    auto cert_path = DataDirectories::ssl_certificate_path();

    if (!fs::exists(cert_path) || !is_certificate_valid(cert_path.u8string())) {
        auto cert_dir = cert_path.parent_path();
        if (!fs::exists(cert_dir)) {
            fs::create_directories(cert_dir);
        }

        LOG((CLOG_NOTE "generating TLS certificate at %s", cert_path.u8string().c_str()));
        generate_pem_self_signed_cert(cert_path.u8string());
    }

    // Publish our own fingerprints so the user can copy them into the peer's
    // TrustedServers.txt / TrustedClients.txt.
    auto local_path = DataDirectories::local_ssl_fingerprints_path();
    auto local_dir = local_path.parent_path();
    if (!fs::exists(local_dir)) {
        fs::create_directories(local_dir);
    }

    FingerprintDatabase db;
    db.add_trusted(get_pem_file_cert_fingerprint(cert_path.u8string(), FingerprintType::SHA1));
    db.add_trusted(get_pem_file_cert_fingerprint(cert_path.u8string(), FingerprintType::SHA256));
    db.write(local_path);

    LOG((CLOG_INFO "local TLS fingerprint: %s",
         format_ssl_fingerprint(
             get_pem_file_cert_fingerprint(cert_path.u8string(),
                                           FingerprintType::SHA256).data).c_str()));
}

} // namespace barrier
