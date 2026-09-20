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
*/

#ifndef BARRIER_LIB_NET_SECUREUTILS_H
#define BARRIER_LIB_NET_SECUREUTILS_H

#include "FingerprintData.h"
#include <openssl/ossl_typ.h>
#include <cstdint>
#include <string>
#include <vector>

namespace barrier {

std::string format_ssl_fingerprint(const std::vector<std::uint8_t>& fingerprint,
                                   bool separator = true);
std::string format_ssl_fingerprint_columns(const std::vector<uint8_t>& fingerprint);

FingerprintData get_ssl_cert_fingerprint(X509* cert, FingerprintType type);

FingerprintData get_pem_file_cert_fingerprint(const std::string& path, FingerprintType type);

void generate_pem_self_signed_cert(const std::string& path);

// True when the PEM at `path` holds a usable key AND has not expired.
bool is_certificate_valid(const std::string& path);

// Makes sure this machine has a TLS identity before it tries to use one:
// generates the self-signed certificate if it is missing or expired, and
// (re)writes this machine's own fingerprints to the Local.txt fingerprint
// file so they can be copied to the peer's trusted list.
//
// This used to be done only by the Qt GUI, which meant a CLI-only install had
// no certificate at all and could not start TLS. Both barriers and barrierc
// call this during startup now.
void ensure_local_certificate();

std::string create_fingerprint_randomart(const std::vector<std::uint8_t>& dgst_raw);

} // namespace barrier

#endif // BARRIER_LIB_NET_SECUREUTILS_H
