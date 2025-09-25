package Koha::Plugin::Com::OpenFifth::QZTray::Controllers::Auth;

use Modern::Perl;
use Mojo::Base 'Mojolicious::Controller';
use Try::Tiny;
use MIME::Base64;
use Crypt::OpenSSL::RSA;

sub getCertificate {
    my $c = shift->openapi->valid_input or return;

    try {
        my $plugin      = Koha::Plugin::Com::OpenFifth::QZTray->new();
        my $certificate = $plugin->retrieve_encrypted_data('certificate_file');

        unless ($certificate) {
            return $c->render(
                json => {
                    error => 'Certificate not configured',
                    error_code => 'CERTIFICATE_NOT_CONFIGURED'
                },
                status  => 404
            );
        }

        return $c->render(
            text   => $certificate,
            status => 200
        );
    }
    catch {
        my $plugin = Koha::Plugin::Com::OpenFifth::QZTray->new();
        $plugin->_log_event('error', 'Certificate retrieval failed', {
            error => "$_",
            action => 'getCertificate',
            endpoint => '/certificate'
        });
        return $c->render(
            json => {
                error => 'Internal server error',
                error_code => 'CERTIFICATE_RETRIEVAL_FAILED'
            },
            status  => 500
        );
    };
}

sub signMessage {
    my $c = shift->openapi->valid_input or return;

    try {
        my $plugin          = Koha::Plugin::Com::OpenFifth::QZTray->new();
        my $private_key_pem = $plugin->retrieve_encrypted_data('private_key_file');

        unless ($private_key_pem) {
            return $c->render(
                json => {
                    error => 'Private key not configured',
                    error_code => 'PRIVATE_KEY_NOT_CONFIGURED'
                },
                status  => 404
            );
        }

        my $body    = $c->validation->param('body');
        my $message = $body->{message};

        unless ($message) {
            return $c->render(
                json => {
                    error => 'Missing message parameter',
                    error_code => 'MESSAGE_PARAMETER_MISSING'
                },
                status  => 400
            );
        }

        # Use Crypt::OpenSSL::RSA for proper RSA signing
        my $rsa = Crypt::OpenSSL::RSA->new_private_key($private_key_pem);
        $rsa->use_sha1_hash();    # QZ Tray uses SHA1

        # Sign the message
        my $signature     = $rsa->sign($message);
        my $signature_b64 = encode_base64( $signature, '' );    # No line breaks

        unless ($signature_b64) {
            die "Failed to generate signature";
        }

        return $c->render(
            text   => $signature_b64,
            status => 200
        );
    }
    catch {
        my $plugin = Koha::Plugin::Com::OpenFifth::QZTray->new();
        $plugin->_log_event('error', 'Message signing failed', {
            error => "$_",
            action => 'signMessage',
            endpoint => '/sign'
        });
        return $c->render(
            json => {
                error => 'Signing failed: ' . $_,
                error_code => 'MESSAGE_SIGNING_FAILED'
            },
            status  => 500
        );
    };
}

1;
