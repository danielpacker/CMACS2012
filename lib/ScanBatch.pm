#!/usr/bin/perl -w
#
# ScanBatch: Do batch simulations with BioNetGen for data collection
# by Daniel Packer
#

package ScanBatch;

use File::Copy;

use constant VALID_PARAMS     => qw/config_file/;
use constant DEFAULT_NUM_RUNS => 100;
use constant MODEL_DIR        => $ENV{'SB_MODEL_DIR'} || '.';
use constant SB_DATA_DIR      => './sb_data';
use constant SB_PREFIX        => 'SB_';

sub new {
  my $class = shift;
  my %params = @_;
  my $self = {};

  # copy valid parameters
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

  my $current_model = '';

  if (my $filename = $self->{'config_file'})
  {
    if (! -e $filename)
    {
      die "file '$filename' not found!";
    } else {
      open ($fh, "<$filename") or die "Couldn't open file '$filename'! $?";

      for my $line (<$fh>)
      {
        $line =~ s/\s+/ /g; # compress extra whitespace
        $line =~ s/^\s*//g; # remove leading whitespace
        $line =~ s/\s*$//g; # remove trailing whitespace
        next if ($line =~ /^\s*$/); # skip blank lines
        next if ($line =~ /^\s*#/); # skip comments

        # get model file context
        if ($line =~ /^\[([\w\.\-]*)\]/g)
        {
          $current_model = $1;
          next; # nothing else to do
        }

        print "line: $line\n";
        # Read the individual params on this line
        my @fields = split(/\s*,\s*/, $line);
        my ($param, $start_val, $end_val, $num_steps) = @fields;
        my $num_runs = (scalar(@fields) == 5) ? pop (@fields) : DEFAULT_NUM_RUNS;

        my %config_entry = (
          'model'     => $current_model,
          'param'     => $param,
          'start_val' => $start_val,
          'end_val'   => $end_val,
          'num_steps' => $num_steps,
          'num_runs'  => $num_runs
          );

        push @config_entries, \%config_entry;
        #print "[$param] [$start_val] [$end_val] [$num_steps]\n";
      }      

      close $fh or die "Error: $?";

      # copy the config entries to object
      $self->{'config_entries'} = [@config_entries];
    }
  }
}

sub dump {

  my $self = shift or die "Call via object!";

  print "\n----------------------------------------------------------------------\n";

  # dump the config filename
  print "\nConfig file:\n" . $self->{'config_file'} . "\n";

  # dump the config entries
  print "\nConfig entries:\n";
  for my $entry (@{ $self->{'config_entries'} })
  {
    print join (", ", (map { $_ . ': ' . $entry->{$_} } (keys %$entry)));
    print "\n";
  }

  print "\n----------------------------------------------------------------------\n";
}


####
#
# Take all of the config entries and do the appropriate scans!
#  
#   

sub batch_scan {

  my $self = shift or die "Call via object!";

  my @config_entries = @{ $self->{'config_entries'} }; # get config entries

  # Pull out the entry to start scanning it
  #my @entry_field_names = qw/model param start_val end_val num_steps num_runs/;
  for my $entry (@config_entries)
  {
    # Does the model exist?
    die "No model defined" unless (exists $entry->{'model'});
    my $model_path = MODEL_DIR . '/' . $entry->{'model'};
    print "MODEL PATH: $model_path\n";
    die "Model file '$model_path' not found!" unless (-e $model_path);

    # Make a local copy of this config file & read the bngl script into memory
    open($fh, "<$model_path") or die "Couldn't open file '$model_path'! $?";
    my $script = "";
    while(<$fh>)
    {
      $script .= $_;
      # Skip actions
      last if (/^\s*end\s*model\s*$/);
    }
    close $fh or die "Couldn't close file '$model_path'! $?";

    if (! -e SB_DATA_DIR) # Create temp dir
    {
      mkdir(SB_DATA_DIR) or die "Couldn't create temp dir '" . SB_DATA_DIR . " $?";
    }

    # Make sure all numeric fields are defined for this entry
    for my $field (qw/start_val end_val num_steps num_runs/)
    {
      die "field $field not defined" unless defined($entry->{$field});
      die "field $field not numeric" unless ($entry->{$field} =~ /^\d+$/);
    }

    # Make local copy of model file to modify
    my $model_path_copy = SB_DATA_DIR . '/' . SB_PREFIX . $entry->{'model'};
    open($copy_fh, ">$model_path_copy") or die "Couldn't create file '$model_path_copy'! $?";
    print $copy_fh $script;

    # Begin the BNGL runs
    for my $run_num (1..$entry->{'num_runs'})
    {
print "RUNNING $run_num times\n";
       my $delta = ($entry->{'end_val'} - $entry->{'start_val'}) / ($entry->{'num_steps'} - 1);
       my $srun= sprintf "%05d", $run_num;
       if ($run_num > 1)
       {
         print $copy_fh "resetConcentrations();\n";
       }
#       my $x= $val;
##      if ($log){ $x= exp($val);}
#       printf $fh_copy "setParameter($var,$x);\n";
#
#       my $prefix = '';
#       my $t_end = 500;       
#       my $stead_state = 1;
#       my $opt= "prefix=>\"$prefix\",suffix=>\"$srun\",t_end=>$t_end,n_steps=>$entry->{'num_steps'}";
#       if ($steady_state)
#       {
#         $opt .= ",steady_state=>1";
#       }
#       printf $fh_copy "simulate_ode({$opt});\n";
#      $val+=$delta;
    }

    close $copy_fh or die "Couldn't save file '$model_path_copy'! $?";

  }

}

1;
