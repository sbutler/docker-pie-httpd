#!/usr/bin/env perl

use warnings;
use strict;

use File::Basename;
use File::Spec::Functions qw/:DEFAULT rel2abs/;
use Getopt::Long;
use IO::Socket::SSL::Utils;
use Log::Dispatch;
use Template;

my $opt_sitesdir = '/etc/opt/pie/apache2/sites';
my $opt_outputdir = '/etc/apache2/sites-pie';
my @opt_includedirs = (
  '/opt/pie/apache2/sites/pie',
);

unless (GetOptions(
  'sitesdir=s'     => \$opt_sitesdir,
  'outputdir=s'    => \$opt_outputdir,
  'includedir=s'   => \@opt_includedirs,
)) {
  print STDERR <<HERE;
Usage: pie-sitegen.pl [options]

Options:
--sitesdir      Location of the PIE formatted sites to process. This defaults
                to /etc/opt/pie/apache2/sites.
--outputdir     Location to place processed templates. This defaults to
                /etc/apache2/sites-pie.
--includedir    Additional include directories for templates. This can be
                specified multiple times to include more than one directory.
                The sitedir is always an include directory. This defaults to
                /opt/pie/apache2/sites/pie.
HERE
  exit 1;
}

my $logger = Log::Dispatch->new(
  outputs => [
    [ 'Screen',
        min_level => 'info',
        newline => 1,
        callbacks => sub {
          my %args = @_;

          return sprintf "[%s] %s", uc $args{ 'level' }, $args{ 'message' };
        }
    ],
  ],
);

unless (-d $opt_sitesdir) {
  $logger->error( "Sites directory does not exist: $opt_sitesdir" );
  exit 1;
}
unless (-d $opt_outputdir) {
  $logger->error("Output directory does not exist: $opt_outputdir" );
  exit 1;
}

my $tt = Template->new({
  INCLUDE_PATH    => [ rel2abs($opt_sitesdir), @opt_includedirs ],
  OUTPUT_PATH     => rel2abs($opt_outputdir),
});
unless ($tt) {
  $logger->error( "Unable to create Template object: " . Template->error );
  exit 2;
}

$logger->info( "Clearing $opt_outputdir/*.conf" );
unlink <"$opt_outputdir/*.conf">;

my $sitesh;
unless (opendir( $sitesh, $opt_sitesdir )) {
  $logger->error( "Cannot open $opt_sitesdir: $!" );
  exit 2;
}

SITEDIR: while (my $sitename = readdir( $sitesh )) {
  my $path = catdir( $opt_sitesdir, $sitename );
  next SITEDIR unless -d $path && $sitename !~ /^[._]/;

  $logger->info( "Processing $sitename ($path)" );
  chdir $path;

  my $template = 'site.conf.tt2';
  unless (-f $template) {
    $logger->warn( "No site.conf.tt2 file in $sitename" );
    next SITEDIR;
  }
  my %template_vars = (
    'name'        => $sitename,
    'ssl_config'  => [],
  );

  process_ssl( \%template_vars );

  $logger->info( "Building $sitename.conf" );
  unless ($tt->process(
    catfile( $sitename, $template ),
    \%template_vars,
    "$sitename.conf"
  )) {
    $logger->warn( "Error processing template for $sitename: " . $tt->error );
    next SITEDIR;
  }
}

sub process_ssl {
  my $vars = shift;

  my $crt_path = 'ssl.crt';
  my $key_path = 'ssl.key';
  my $chn_path = 'ssl.chn';

  return unless -d $crt_path && -d $key_path;

  my $crt_glob = catfile( $crt_path, "*.crt" );
  SSLCRT: while (my $crt = <"$crt_glob">) {
    my $name = fileparse( $crt, '.crt' );

    my $key = catfile( $key_path, "$name.key" );
    unless (-f $key) {
      $logger->warn( "Key file not found: $key" );
      next SSLCRT;
    }

    my $chn = catfile( $chn_path, "$name.crt" );

    $logger->info( "Reading SSL certificate: $crt" );
    my ($crt_obj, $crt_hash);
    eval {
      $crt_obj = PEM_file2cert( $crt );
      $crt_hash = CERT_asHash( $crt_obj );
    };
    my $crt_err = $@;
    if ($crt_obj) {
      eval { CERT_free( $crt_obj ); $crt_obj = undef; }
    }
    if ($crt_err || !$crt_hash) {
      $logger->warn( "Error reading file $crt: $crt_err" );
      next SSLCRT;
    }

    my $crt_subject = lc $crt_hash->{ 'subject' }{ 'commonName' };
    my @crt_san = map { $_->[ 0 ] eq 'DNS' ? lc( $_->[ 1 ] ) : () } @{$crt_hash->{ 'subjectAltNames' }};

    push @{$vars->{ 'ssl_config' }}, {
      'name'            => $name,
      'certificate'     => rel2abs( $crt ),
      'key'             => rel2abs( $key ),
      'chain'           => (-f $chn ? rel2abs( $chn ) : undef),
      'subject'         => $crt_subject,
      'subjectAltNames' => \@crt_san,
    };
  }
}
