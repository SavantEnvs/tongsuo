/*
 * CMS EnvelopedData decryption with a password recipient (RFC 3211 PWRI key unwrap).
 * The input is a DER CMS message; it is parsed and, when it is EnvelopedData, decrypted with a fixed
 * password through the public CMS_decrypt_set1_password()/CMS_decrypt() API.
 */
#include <stddef.h>
#include <stdint.h>
#include <openssl/bio.h>
#include <openssl/cms.h>
#include <openssl/err.h>

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void)argc;
    (void)argv;
    OPENSSL_init_crypto(OPENSSL_INIT_LOAD_CRYPTO_STRINGS, NULL);
    ERR_clear_error();
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *buf, size_t len)
{
    static const unsigned char password[] = "password";
    CMS_ContentInfo *cms;
    BIO *in, *out;

    if (len == 0)
        return -1;

    in = BIO_new_mem_buf(buf, (int)len);
    if (in == NULL)
        return -1;
    cms = d2i_CMS_bio(in, NULL);
    BIO_free(in);
    if (cms != NULL) {
        out = BIO_new(BIO_s_null());
        if (out != NULL
            && CMS_decrypt_set1_password(cms, (unsigned char *)password,
                                         sizeof(password) - 1) > 0)
            CMS_decrypt(cms, NULL, NULL, NULL, out, 0);
        BIO_free(out);
        CMS_ContentInfo_free(cms);
    }
    ERR_clear_error();
    return 0;
}
