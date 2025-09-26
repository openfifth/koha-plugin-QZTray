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

sub logError {
    my $c = shift->openapi->valid_input or return;

    try {
        my $plugin = Koha::Plugin::Com::OpenFifth::QZTray->new();
        my $body   = $c->validation->param('body');

        # Extract error details
        my $error_message = $body->{error} || 'Unknown error';
        my $context       = $body->{context} || 'unknown_context';
        my $user_agent    = $body->{user_agent} || 'unknown_user_agent';
        my $page_url      = $body->{page_url} || 'unknown_url';

        # Validate required fields
        unless ($error_message) {
            return $c->render(
                json => {
                    error => 'Missing required field: error',
                    error_code => 'MISSING_ERROR_MESSAGE'
                },
                status => 400
            );
        }

        # Log the client-side error
        $plugin->_log_event('error', 'Client-side error', {
            client_error => $error_message,
            context => $context,
            user_agent => $user_agent,
            page_url => $page_url,
            timestamp => scalar(localtime()),
            action => 'client_error_log',
            endpoint => '/log-error'
        });

        return $c->render(
            json => {
                status => 'logged'
            },
            status => 200
        );
    }
    catch {
        my $plugin = Koha::Plugin::Com::OpenFifth::QZTray->new();
        $plugin->_log_event('error', 'Error logging client error', {
            error => "$_",
            action => 'logError',
            endpoint => '/log-error'
        });
        return $c->render(
            json => {
                error => 'Failed to log error',
                error_code => 'ERROR_LOGGING_FAILED'
            },
            status => 500
        );
    };
}

1;
