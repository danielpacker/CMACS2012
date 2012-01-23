#
# Statstics functionality for processing BioNetGen data
# by Daniel Packer

package ScanBatch::Stats;

use strict;
use warnings;

use Statistics::R;
use File::Find;


my @data_files = ();

sub new {
  my $class = shift;
  my $self = {};
  my %params = @_;

  my %defaults = (
    'data_dir'  => '.',
    'out_dir'  => '.',
    );

  %params = map { defined($params{$_}) ? $params{$_} : $defaults{$_} } (keys %defaults);

  $self->{'R'} = Statistics::R->new();

  bless $self, $class;
}


sub find_data_files {
  my $self = shift;
  die "Call via object!" unless defined($self);

  my $find_path = shift;
  die "No find_path defined" unless defined($find_path);

  # Get list of all data files in dir find_path
  die "find_path not defined" unless defined($self->{'data_files_path'});
  sub wanted {
    push(@data_files, $File::Find::name) if (/.*\.gdat/);
  }
  find(\&wanted, $find_path);
  #print map { "$_\n" } @data_files;
}

sub get_activation_times {

  my $self = shift;
  die "Call via object!" unless defined($self);
  my %params = @_;

  my %defaults = (
    'time_field' => 0,
    'data_field' => 1,
    'data_threshhold' => 0,
    );

  %params = map { defined($params{$_}) ? $params{$_} : $defaults{$_} } (keys %defaults);

  # skim times off of files
  my @times = ();
  my $time_field = $params{'time_field'};
  my $data_field = $params{'data_field'};
  my $data_threshhold = $params{'data_threshhold'};

  for my $file (@data_files)
  {
    print "Opening file '$file'\n";
    open my $fh, "<$file" or die "Couldn't open file '$file': $!";
    while (my $line = <$fh>)
    {
      $line =~ s/^\s+//g; # remove leading white space
      next if ($line =~ /^\s*\#/);
      my @fields = split(/\s+/, $line);
      my ($time, $data) = ($fields[$time_field], $fields[$data_field]);
      next if ($time == 0); # skip time zero
      if ($data > $data_threshhold)
      {
        push @times, $time;
        last;
      }    
    }
    close $fh;
  }
  return @times;
}

#use Data::Dumper; print Dumper \@times;

#print "Number of times: " . scalar(@times) . "\n";

sub generate_cdf {
  my $self = shift;
  die "Call via object!" unless defined($self);
  my %params = @_;

  my %defaults = (
    'output_dir'  => '.',
    'values'      => [],
    'display_cdf' => 0,
    );

  %params = map { defined($params{$_}) ? $params{$_} : $defaults{$_} } (keys %defaults);

  my @times = @{ $params{'values'} };

  my $formatted_times = join(', ', reverse sort(@times));
  #print "formatted_times = $formatted_times\n";

  my $output_file = $params{'output_dir'} . '/' . 'cdf.ps';
  my $R = $self->{'R'};
  $R->run(qq`postscript("$output_file" , horizontal=FALSE , width=500 , height=500 , pointsize=12)`);
  $R->run(qq`x <- c($formatted_times);`);
  $R->run(qq`plot(ecdf(x), verticals=TRUE, do.points=FALSE);`);
  $R->stop();

  exec("ghostscript $output_file") if ($params{'display_cdf'});
}

1;
