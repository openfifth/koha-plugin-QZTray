package Koha::Plugin::Com::OpenFifth::QZTray;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use C4::Context;
use Koha::DateUtils;
use JSON qw( decode_json );

our $VERSION         = '1.0.2';
our $MINIMUM_VERSION = "22.05.00.000";

our $metadata = {
    name            => 'QZ Tray Integration',
    author          => 'OpenFifth',
    description     => 'QZ Tray printing integration for Koha',
    date_authored   => '2025-01-31',
    date_updated    => '2025-09-24',
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
        my $template =
          $self->get_template( { file => 'templates/configure.tt' } );

        $template->param(
            certificate_file  => $self->retrieve_data('certificate_file') || '',
            private_key_file  => $self->retrieve_data('private_key_file') || '',
            preferred_printer => $self->retrieve_data('preferred_printer')
              || '',
        );

        $self->output_html( $template->output() );
    }
    else {
        my @errors;

        # Handle certificate file upload
        my $cert_upload = $cgi->upload('certificate_upload');
        if ($cert_upload) {
            if ( not defined $cert_upload ) {
                push @errors,
                  "Failed to get certificate file: " . $cgi->cgi_error;
            }
            else {
                my $cert_content;
                while ( my $line = <$cert_upload> ) {
                    $cert_content .= $line;
                }
                if ($cert_content) {
                    $self->store_data( { certificate_file => $cert_content } );
                }
                else {
                    push @errors, "Certificate file appears to be empty";
                }
            }
        }

        # Handle private key file upload
        my $key_upload = $cgi->upload('private_key_upload');
        if ($key_upload) {
            if ( not defined $key_upload ) {
                push @errors,
                  "Failed to get private key file: " . $cgi->cgi_error;
            }
            else {
                my $key_content;
                while ( my $line = <$key_upload> ) {
                    $key_content .= $line;
                }
                if ($key_content) {
                    $self->store_data( { private_key_file => $key_content } );
                }
                else {
                    push @errors, "Private key file appears to be empty";
                }
            }
        }

        # Store other configuration
        $self->store_data(
            {
                preferred_printer => $cgi->param('preferred_printer') || '',
            }
        );

        if (@errors) {
            my $template =
              $self->get_template( { file => 'templates/configure.tt' } );
            $template->param( errors => \@errors );
            $self->output_html( $template->output() );
        }
        else {
            $self->go_home();
        }
    }
}

sub intranet_js {
    my ($self) = @_;

    # Always load in staff interface when plugin is enabled and configured
    my $certificate = $self->retrieve_data('certificate_file') || '';
    my $private_key = $self->retrieve_data('private_key_file') || '';

    return '' unless ( $certificate && $private_key );

    return $self->_generate_qz_js();
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

sub api_namespace {
    my ($self) = @_;
    return 'qztray';
}

sub static_routes {
    my ( $self, $args ) = @_;
    my $spec_str = $self->mbf_read('api/staticapi.json');
    my $spec     = decode_json($spec_str);
    return $spec;
}

sub api_routes {
    my ( $self, $args ) = @_;
    my $spec_str = $self->mbf_read('api/openapi.json');
    my $spec     = decode_json($spec_str);
    return $spec;
}

sub _generate_qz_js {
    my ($self) = @_;

    # Static routes are served at /api/v1/contrib/{namespace}/static{route}
    my $static_base = "/api/v1/contrib/" . $self->api_namespace . "/static";

    # Get preferred printer setting
    my $preferred_printer = $self->retrieve_data('preferred_printer') || '';

    # Escape JavaScript strings for preferred printer only
    $preferred_printer =~ s/\\/\\\\/g;
    $preferred_printer =~ s/'/\\'/g;
    $preferred_printer =~ s/\n/\\n/g;

    # API routes are served at /api/v1/contrib/{namespace}{route}
    my $api_base = "/api/v1/contrib/" . $self->api_namespace;

    return qq{
<!-- QZ Tray JavaScript Libraries (loaded as external files) -->
<script type="text/javascript" src="$static_base/js/rsvp-3.1.0.min.js"></script>
<script type="text/javascript" src="$static_base/js/sha-256.min.js"></script>
<script type="text/javascript" src="$static_base/js/jsrsasign-all-min.js"></script>
<script type="text/javascript" src="$static_base/js/qz-tray.js"></script>

<script type="text/javascript">
// QZ Tray Configuration
window.qzConfig = {
    apiBase: '$api_base',
    preferredPrinter: '$preferred_printer'
};


// QZ Tray Cash Drawer Functionality (global scope)
function displayError(err) {
  console.error(err);
}

function chr(i) {
  return String.fromCharCode(i);
}

function drawerCode(printer) {
  var code = [chr(27) + chr(112) + chr(48) + chr(55) + chr(121)]; //default code
  
  // Handle case where printer is undefined or null
  if (!printer || typeof printer !== 'string') {
    console.log('No printer name provided, using default drawer code');
    return code;
  }
  
  if (printer.indexOf('Bixolon SRP-350') !== -1 ||
    printer.indexOf('Epson TM-T88V') !== -1 ||
    printer.indexOf('Metapace T') !== -1 ) {
    code = [chr(27) + chr(112) + chr(48) + chr(55) + chr(121)];
  }
  if (printer.indexOf('Citizen CBM1000') !== -1) {
    code = [chr(27) + chr(112) + chr(0) + chr(50) + chr(250)];
  }
  return code;
}

// Track drawer operations separately from form submissions
var drawerInProgress = false;


// get signed certificate to suppress security prompts, connect to qz tray app
// select default printer, find drawer open code using drawerCode(), send command to the printer
// after drawer has opened hide the drawer open button and show the default button for
// the given page - element selector is passed in parameter s, h for hide class
function popDrawer(s, h) {

  // Prevent duplicate submissions
  if (drawerInProgress) {
    return false;
  }
  drawerInProgress = true;

  // Set up certificate loading from API (secure)
  qz.security.setCertificatePromise(function(resolve, reject) {
    fetch(window.qzConfig.apiBase + '/certificate', {
      method: 'GET',
      cache: 'no-store',
      credentials: 'same-origin'
    }).then(function(response) {
      if (response.ok) {
        return response.text();
      } else {
        throw new Error('Certificate not configured');
      }
    }).then(function(certificate) {
      resolve(certificate);
    }).catch(function(error) {
      console.error('Failed to load certificate:', error);
      resolve('');
    });
  });
  
  // Set up message signing via API (secure)
  qz.security.setSignaturePromise(function(toSign) {
    return function(resolve, reject) {
      fetch(window.qzConfig.apiBase + '/sign', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        credentials: 'same-origin',
        body: JSON.stringify({ message: toSign })
      }).then(function(response) {
        if (response.ok) {
          return response.text();
        } else {
          throw new Error('Signing failed');
        }
      }).then(function(signature) {
        resolve(signature);
      }).catch(function(error) {
        console.error('Failed to sign message:', error);
        resolve('');
      });
    };
  });
  
  qz.websocket
    .connect()
    .then(function() {
      console.log('QZ Tray connected successfully');
      // Check if we have a preferred printer configured
      var preferredPrinter = window.qzConfig.preferredPrinter;
      if (preferredPrinter) {
        return Promise.resolve(preferredPrinter);
      } else {
        return qz.printers.getDefault();
      }
    })
    .then(function(printer) {
      var config = qz.configs.create(printer);
      var data = drawerCode(printer);
      return qz.print(config, data);
    })
    .then(function() {
      console.log('Cash drawer command sent successfully');
      \$('.' + h).hide();
      \$('.' + s).show();
      return qz.websocket.disconnect();
    })
    .catch(function(error) {
      console.log('QZ Tray operation failed:', error.message || error);
      displayError(error);
      \$('.' + h).hide();
      \$('.' + s).show();
      return qz.websocket.disconnect();

    })
    .finally(function() {
      setTimeout(function() {
        drawerInProgress = false;
      }, 500);
    });
}

// array used to hide default button, add cash drawer button (renamed to same as default button)
// hide cash drawer button after clicking, rename default button and show it
// [0] - partial url for matching pages
// [1] - element defining the default button for a given page
// [2] - text to use when renaming button that opens cash drawer
// [3] - text to use when renaming default button
var buttonscontinue = [
  ['pos/pay.pl', '#submitbutton', 'Confirm', 'Commit payment'],
  ['pos/register.pl', '#pos_cashup', 'Record cashup', 'Continue cashup'],
  ['pos/register.pl', '#pos_refund_confirm', 'Refund', 'Commit refund'],
  ['pos/registers.pl', '.cashup_all', 'Cashup all', 'Continue cashup'],
  ['pos/registers.pl', 'button[data-register\$="Till"]', 'Start cashup', 'Continue cashup'],
  ['members/boraccount.pl', '#borr_payout_confirm', 'Confirm', 'Commit payout'],
  ['members/paycollect.pl', '#paysubmit', 'Confirm', 'Commit payment'],
];

// Wait for DOM to be ready
\$(document).ready(function() {
  // function to match on a page in the buttonscontinue array
  // when a match is found, change the text of the default button and hide it
  // add a new button with the original text of the default button to open the till drawer
  // adds class to buttons containing a random number which is passed to popDrawer to show/hide correct buttons on click
  buttonscontinue.forEach(function(b, i) {
    if (window.location.href.indexOf(b[0]) !== -1) {
      \$(b[1]).each(function() {
        var r = Math.floor(Math.random() * 100000) + 1;
        var originalClasses = \$(this).attr('class') || '';
        var originalType = this.type || 'button';

        \$(this).text(b[3]);
        \$(this).prop('value', b[3]);
        \$(this).addClass('s' + r);
        \$(\$(this)).hide();

        \$(
          '<input type="' + originalType + '" class="' + originalClasses + ' drawer-button' +
          r +
          '" id="drawer-button" value="' +
          b[2] +
          '" onclick="popDrawer(\\'s' +
          r +
          "\\',\\'drawer-button" +
          r +
          '\\');return false;" />'
        ).insertBefore(\$(this));
      });
    }
  });
});
</script>
    };
}

sub _read_js_file {
    my ( $self, $file_path ) = @_;

    # Use mbf_read to read file from plugin bundle
    my $content = $self->mbf_read($file_path);

    if ($content) {

        # Clean up the content to avoid JavaScript syntax issues
        $content =~ s/\r\n/\n/g;       # Normalize line endings
        $content =~ s/\r/\n/g;         # Convert remaining CR to LF
        $content = $content . "\n";    # Ensure ends with newline

        return $content;
    }

    return "// File not found via mbf_read: $file_path";
}

sub _escape_js_content {
    my ( $self, $content ) = @_;

    # Convert any non-ASCII characters to JavaScript Unicode escape sequences
    # This handles any Unicode character that might cause syntax errors
    $content =~ s/([^\x00-\x7F])/sprintf("\\u%04X", ord($1))/ge;

    return $content;
}

1;
