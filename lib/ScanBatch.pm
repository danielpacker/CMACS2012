#!/usr/bin/perl -w

package ScanBatch;

use constant VALID_PARAMS => qw/config_file/;

sub new {
  my $class = shift;
  my %params = @_;
  my $self = {};

  # copy valid paramters
  for my $key (keys %params)
  {
    if (grep(VALID_PARAMS, $key))
    {
      if (exists $params{$key}) 
      {
        $self->{$key} = $params{$key};

        # Specific param handling
        if ($key eq 'config_file')
        {
          die("Can't find file '" . $params{$key} . "'")
            unless(-e $params{'config_file'});
        }
      }
    }
  }

  my $obj = bless $self, $class;
  $obj->read_conf();
  return $obj;
}


# Read the config file referenced $self->{'config_file'}
sub read_conf {

  my $self = shift or die "Call via object!";

  my @config_entries = ();

  if (my $filename = $self->{'config_file'})
  {

    if (! -e $filename)
    {
      die "file '$filename' not found!";
    } else {
      open ($fh, "<$filename") or die "Couldn't open file '$filename'! $!";

      for my $line (<$fh>)
      {
        $line =~ s/\s+/ /g; # compress extra whitespace
        $line =~ s/^\s*//g; # remove leading whitespace
        $line =~ s/\s*$//g; # remove trailing whitespace
        next if ($line =~ /^\s*$/); # skip blank lines
        next if ($line =~ /^\s*#/); # skip comments
        #print "line: $line\n";

        my ($param, $start_val, $end_val, $num_steps) =
          split(/\s*,\s*/, $line);

        my %config_entry = (
          'param'     => $param,
          'start_val' => $start_val,
          'end_val'   => $end_val,
          'num_steps' => $num_steps
          );

        push @config_entries, \%config_entry;
        #print "[$param] [$start_val] [$end_val] [$num_steps]\n";
      }      

      close $fh or die "$!";

      # save the config entries to object
      $self->{'config_entries'} = [@config_entries];
    }
  }
}

sub dump {

  my $self = shift or die "Call via object!";

  # dump the config filename
  print "\nConfig file:\n" . $self->{'config_file'} . "\n";

  # dump the config entries
  print "\nConfig entries:\n";
  for my $entry (@{ $self->{'config_entries'} })
  {
    print join (", ", (map { $_ . ': ' . $entry->{$_} } (keys %$entry)));
    print "\n";
  }
}

1;
