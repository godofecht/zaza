#include <iostream>
#include <curl/curl.h>
#include <zlib.h>
#include <mbedtls/version.h>

int main() {
    std::cout << "cmake_net" << std::endl;
    std::cout << "curl: " << curl_version() << std::endl;
    std::cout << "zlib: " << zlibVersion() << std::endl;
    std::cout << "mbedtls: " << MBEDTLS_VERSION_STRING << std::endl;
    return 0;
}
