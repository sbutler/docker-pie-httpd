#!/usr/bin/env perl

use warnings;
use strict;

use File::Basename;
use File::Spec::Functions qw/:DEFAULT rel2abs/;
use Getopt::Long;
use IO::Socket::SSL::Utils;
use Template;

my $opt_sitesdir = '/etc/opt/pie/apache2/sites';
my $opt_outputdir = '/etc/apache2/sites-pie';

unless (GetOptions(
  'sitesdir=s'     => \$opt_sitesdir,
  'outputdir=s'    => \$opt_outputdir
)) {
  print STDERR <<HERE;
Usage: pie-sitegen.pl [options]

Options:
--sitesdir      Location of the PIE formatted sites to process. This defaults
                to /etc/opt/pie/apache2/sites.
--outputdir     Location to place processed templates. This defaults to
                /etc/apache2/sites-pie.
HERE
  exit 1;
}

unless (-d $opt_sitesdir) {
  printf STDERR "Sites directory does not exist: %s\n", $opt_sitesdir;
  exit 1;
}
unless (-d $opt_outputdir) {
  printf STDERR "Output directory does not exist: %s\n", $opt_outputdir;
  exit 1;
}

my $tt = Template->new({
  INCLUDE_PATH    => rel2abs($opt_sitesdir),
  OUTPUT_PATH     => rel2abs($opt_outputdir),
});
unless ($tt) {
  printf STDERR "Unable to create Template object: %s\n", Template->error;
  exit 2;
}

# Clean out the output directory
unlink <"$opt_outputdir/*.conf">;

my $sitesh;
unless (opendir( $sitesh, $opt_sitesdir )) {
  printf STDERR "Cannot open %s: %s\n", $opt_sitesdir, $!;
  exit 2;
}

SITEDIR: while (my $sitename = readdir( $sitesh )) {
  my $path = catdir( $opt_sitesdir, $sitename );
  next SITEDIR unless -d $path && $sitename !~ /^[._]/;

  chdir $path;

  my $template = 'site.conf.template';
  unless (-f $template) {
    printf STDERR "No site.conf.template file in %s\n", $sitename;
    next SITEDIR;
  }
  my %template_vars = (
    'name'        => $sitename,
    'ssl_config'  => [],
  );

  process_ssl( \%template_vars );

  unless ($tt->process(
    catfile( $sitename, $template ),
    \%template_vars,
    "$sitename.conf"
  )) {
    printf STDERR "Error processing template %s: %s\n", $sitename, $tt->error;
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
      printf STDERR "No key file for SSL certificate %s\n", $crt;
      next SSLCRT;
    }

    my $chn = catfile( $chn_path, "$name.crt" );

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
      printf STDERR "Unable to read SSL certificate file %s: %s\n", $crt, $crt_err;
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
