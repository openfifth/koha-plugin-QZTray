package Koha::Plugin::Com::OpenFifth::QZTray;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use C4::Context;
use Koha::DateUtils;

our $VERSION = '1.0.0';
our $MINIMUM_VERSION = "22.05.00.000";

our $metadata = {
    name            => 'QZ Tray Integration',
    author          => 'OpenFifth',
    description     => 'QZ Tray printing integration for Koha',
    date_authored   => '2025-01-31',
    date_updated    => '2025-01-31',
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'templates/configure.tt' } );

        $template->param(
            certificate_file => $self->retrieve_data('certificate_file') || '',
            private_key_file => $self->retrieve_data('private_key_file') || '',
            enable_staff     => $self->retrieve_data('enable_staff') || 0,
            enable_opac      => $self->retrieve_data('enable_opac') || 0,
        );

        $self->output_html( $template->output() );
    } else {
        my @errors;

        # Handle certificate file upload
        my $cert_upload = $cgi->upload('certificate_upload');
        if ( $cert_upload ) {
            my $cert_content = $self->_read_upload($cert_upload);
            if ( $cert_content ) {
                $self->store_data({ certificate_file => $cert_content });
            } else {
                push @errors, "Failed to read certificate file";
            }
        }

        # Handle private key file upload
        my $key_upload = $cgi->upload('private_key_upload');
        if ( $key_upload ) {
            my $key_content = $self->_read_upload($key_upload);
            if ( $key_content ) {
                $self->store_data({ private_key_file => $key_content });
            } else {
                push @errors, "Failed to read private key file";
            }
        }

        # Store other configuration
        $self->store_data({
            enable_staff => $cgi->param('enable_staff') || 0,
            enable_opac  => $cgi->param('enable_opac') || 0,
        });

        if ( @errors ) {
            my $template = $self->get_template( { file => 'templates/configure.tt' } );
            $template->param( errors => \@errors );
            $self->output_html( $template->output() );
        } else {
            $self->go_home();
        }
    }
}

sub intranet_js {
    my ( $self ) = @_;
    
    return '' unless $self->retrieve_data('enable_staff');
    
    my $certificate = $self->retrieve_data('certificate_file') || '';
    my $private_key = $self->retrieve_data('private_key_file') || '';
    
    return '' unless ( $certificate && $private_key );
    
    return $self->_generate_qz_js( $certificate, $private_key );
}

sub opac_js {
    my ( $self ) = @_;
    
    return '' unless $self->retrieve_data('enable_opac');
    
    my $certificate = $self->retrieve_data('certificate_file') || '';
    my $private_key = $self->retrieve_data('private_key_file') || '';
    
    return '' unless ( $certificate && $private_key );
    
    return $self->_generate_qz_js( $certificate, $private_key );
}

sub install {
    my ( $self, $args ) = @_;
    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;
    return 1;
}

sub uninstall {
    my ( $self, $args ) = @_;
    return 1;
}

sub _read_upload {
    my ( $self, $upload ) = @_;
    
    return unless $upload;
    
    # Read the entire file content using slurp mode
    my $fh = $upload;
    local $/;
    my $content = <$fh>;
    
    return $content;
}


sub _generate_qz_js {
    my ( $self, $certificate, $private_key ) = @_;
    
    # Escape JavaScript strings
    $certificate =~ s/\\/\\\\/g;
    $certificate =~ s/'/\\'/g;
    $certificate =~ s/\n/\\n/g;
    
    $private_key =~ s/\\/\\\\/g;
    $private_key =~ s/'/\\'/g;
    $private_key =~ s/\n/\\n/g;
    
    return qq{
<script type="text/javascript">
// QZ Tray Configuration
window.qzConfig = {
    certificate: '$certificate',
    privateKey: '$private_key'
};

// Load QZ Tray dependencies and main library
(function() {
    var scripts = [
        '/plugin/Koha/Plugin/Com/OpenFifth/QZTray/js/dependencies/rsvp-3.1.0.min.js',
        '/plugin/Koha/Plugin/Com/OpenFifth/QZTray/js/dependencies/sha-256.min.js',
        '/plugin/Koha/Plugin/Com/OpenFifth/QZTray/js/qz-tray.js'
    ];
    
    function loadScript(index) {
        if (index >= scripts.length) {
            // All scripts loaded, initialize QZ Tray
            if (typeof initQZTray === 'function') {
                initQZTray();
            }
            return;
        }
        
        var script = document.createElement('script');
        script.src = scripts[index];
        script.onload = function() {
            loadScript(index + 1);
        };
        script.onerror = function() {
            console.error('Failed to load QZ Tray script: ' + scripts[index]);
            loadScript(index + 1);
        };
        document.head.appendChild(script);
    }
    
    loadScript(0);
})();
</script>
    };
}

1;
