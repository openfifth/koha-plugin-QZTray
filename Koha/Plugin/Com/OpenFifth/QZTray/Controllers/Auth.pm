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
        my $certificate = $plugin->retrieve_data('certificate_file');

        unless ($certificate) {
            return $c->render(
                openapi => { error => 'Certificate not configured' },
                status  => 404
            );
        }

        return $c->render(
            text   => $certificate,
            status => 200
        );
    }
    catch {
        warn "Error retrieving certificate: $_";
        return $c->render(
            openapi => { error => 'Internal server error' },
            status  => 500
        );
    };
}

sub signMessage {
    my $c = shift->openapi->valid_input or return;

    try {
        my $plugin          = Koha::Plugin::Com::OpenFifth::QZTray->new();
        my $private_key_pem = $plugin->retrieve_data('private_key_file');

        unless ($private_key_pem) {
            return $c->render(
                openapi => { error => 'Private key not configured' },
                status  => 404
            );
        }

        my $body    = $c->validation->param('body');
        my $message = $body->{message};

        unless ($message) {
            return $c->render(
                openapi => { error => 'Missing message parameter' },
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
        warn "Error signing message: $_";
        return $c->render(
            openapi => { error => 'Signing failed: ' . $_ },
            status  => 500
        );
    };
}

1;
