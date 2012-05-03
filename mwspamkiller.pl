#!/usr/bin/perl -w

# This is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This file is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this file; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA

use MediaWiki::Bot;
use MediaWiki::Bot::Plugin::Admin;
use YAML::Syck qw'LoadFile DumpFile';
$YAML::Syck::ImplicitUnicode = 1;
use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use Modern::Perl;

my $goodusersfile = 'goodusers.yaml';
my ($configfile, $verbose, $debug) = get_options();

# Open the config
if ( !-e $configfile ) {
  die "Could not find $configfile\n";
}
my ($config) = LoadFile($configfile);
my %goodusers = LoadFile($goodusersfile);

# Set up a Mediawiki bot 
my $bot = MediaWiki::Bot->new({
	assert      => 'bot',
}) or die "Could not create bot";

# Choose the wiki
if ($debug) { print "Wiki: ", $config->{wikihost}, " / ", $config->{wikipath}, "\n"; }
$bot->set_wiki({
	host        => $config->{wikihost},
	path        => $config->{wikipath},
}) or die "Could not set wiki";

# Log in to the wiki
if ($debug) { print "Wiki user: ", $config->{wikiuser}, ":", $config->{wikipass}, "\n"; }
# Make sure we are logged out first
$bot->logout();
$bot->login({
	username => $config->{wikiuser},
	password => $config->{wikipass},
}) or die "Login failed ", $bot->{'error'}->{'code'}, " ", $bot->{'error'}->{'details'};
if ($debug) { print "Logged in to the wiki\n"; }

my @users = $bot->get_allusers();
foreach my $user ( @users ) {
  if ( $bot->is_blocked( $user ) ) {
    print "$user BLOCKED\n" if $verbose;
  } elsif ( $goodusers{$user} ) {
    print "$user GOOD USER\n" if $verbose;
  } else {
  
    print "$user\n";
  
    # Main
    my @mainns = (0);
    my @maincontribs = $bot->contributions( $user, \@mainns );

    # User
    my @userns = (2);
    my @usercontribs = $bot->contributions( $user, \@userns );

    # A common array
    my @contribs;
    push @contribs, @maincontribs;
    push @contribs, @usercontribs;

    # Print pages
    foreach my $contrib ( @contribs ) {
      print Dumper $contrib if $debug;
      print "\t* ", $contrib->{'title'}, "\n";
      print "\tBruker: ", $contrib->{'user'}, "\n";
      print "\t", $contrib->{'comment'}, "\n";
    }
    
    print "Good or bad? [Gb]: ";
    my $gb = <>;
    chomp($gb);
    if ($gb eq 'b' || $gb eq 'B') {
      # Delete pages
      # FIXME This will only work as long as the user did not edit existing 
      # pages...
      foreach my $contrib ( @contribs ) {
        print "\tDeleting ", $contrib->{'title'}, "...\n";
        $bot->delete($contrib->{'title'}, 'Sletting av spam');
      }
      # Block user
      print "\tBlocking $user...\n";
      $bot->block({
        user        => $user,
        length      => 'infinite',
        summary     => 'Spam',
        anononly    => 1,
        autoblock   => 1,
      });
    } else {
      $goodusers{$user}++;
      # Save immediately
      DumpFile($goodusersfile, %goodusers);
    }
  }
}

###

# Get commandline options
sub get_options {
  my $configfile  = '';
  my $verbose     = '';
  my $debug       = '';
  my $help        = '';

  GetOptions("c|config=s"  => \$configfile,
             "v|verbose"   => \$verbose,
             "d|debug"     => \$debug,
             "h|help"      => \$help,
             );
  
  pod2usage(-exitval => 0) if $help;
  pod2usage( -msg => "\nMissing Argument: -c, --config required\n", -exitval => 1) if !$configfile;

  return ($configfile, $verbose, $debug);
}       

__END__

=head1 NAME
    
mwspamkiller.pl - Delete spammers and their pages from a Mediawiki-site
        
=head1 SYNOPSIS
            
mwspamkiller.pl -c myconfig.yaml

=head1 OPTIONS
              
=over 8

=item B<-c, --config>

Path to a config file in YAML format. 

=item B<-v, --verbose>

Turn on verbose output. 

=item B<-d, --debug>

Turn on debug output. 

=item B<-h, --help>

Print this documentation. 

=back
                                                               
=cut
