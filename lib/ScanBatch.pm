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
use constant BNG_PATH         => $ENV{'BNGPATH'} || '.';

# BNGL code for equilibrium
use constant EQUIL_CODE       => qq(
generate_network({overwrite => 1});
simulate_ode({suffix=>"equil",t_end=>100,n_steps=>100,atol=>1e-10,rtol=>1e-8,steady_state=>1,sparse=>1});
saveConcentrations();
);


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

  my %config_entries = ();

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

        # Organize entries by model name
        if (! exists($config_entries{$config_entry{'model'}}) )
        {
          $config_entries{$config_entry{'model'}} = [];
        }
        push @{ $config_entries{$config_entry{'model'}} }, \%config_entry;
        #print "[$param] [$start_val] [$end_val] [$num_steps]\n";
      }      

      close $fh or die "Error: $?";

      # copy the config entries to object
      $self->{'config_entries'} = {%config_entries};
    }
  }
}

sub dump {

  my $self = shift or die "Call via object!";

  print "\n----------------------------------------------------------------------\n";

  # dump the config filename
  print "\nConfig file: " . $self->{'config_file'} . "\n";

  # dump the config entries
  print "\n=== Config entries ===\n";
  for my $model (keys %{ $self->{'config_entries'} })
  {
    print "Model '$model':\n";
    my @entries = @{ $self->{'config_entries'}->{$model} };
    for my $entry (@entries)
    {
      print join (", ", (map { $_ . ': ' . $entry->{$_} } (keys %$entry)));
      print "\n";
    }
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

  my %config_entries = %{ $self->{'config_entries'} }; # get config entries

  # Work on one model at a time

  for my $model (keys %config_entries)
  {
    # Does the model exist?
    die "No model defined" unless (exists $config_entries{$model});
    my $model_path = MODEL_DIR . '/' . $model;
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

    # Make local copy of model file to modify
    my $model_path_copy = SB_DATA_DIR . '/' . SB_PREFIX . $model;
    open($fh_copy, ">$model_path_copy") or die "Couldn't create file '$model_path_copy'! $?";
    print $fh_copy $script;

    # Process the config entries for this model
    my @extracted_entries = @{ $config_entries{$model} };

    # Pull out the entry to start scanning it
    #my @entry_field_names = qw/model param start_val end_val num_steps num_runs/;
    for my $entry (@extracted_entries)
    {

      # Make sure all numeric fields are defined for this entry
      for my $field (qw/start_val end_val num_steps num_runs/)
      {
        die "field $field not defined" unless defined($entry->{$field});
        die "field $field not numeric" unless ($entry->{$field} =~ /^\d+$/);
      }

      print $fh_copy "\n# Added by BatchScan - Equilibriation:" . EQUIL_CODE;
      print $fh_copy "\n# Added by BatchScan - Setting paramters for '$entry->{'param'}':\n";

      # Begin the BNGL runs
      my $current_val = $entry->{'start_val'};

      for my $run_num (1..$entry->{'num_runs'})
      {
        my $delta = ($entry->{'end_val'} - $entry->{'start_val'}) / ($entry->{'num_steps'} - 1);
  #print "DELTA for $entry->{'param'}: $delta";
        my $srun= sprintf "%05d", $run_num;
        if ($run_num > 1)
        {
          print $fh_copy "resetConcentrations();\n";
        }
        printf $fh_copy "setParameter($entry->{'param'}, $current_val);\n";
        my $prefix = '';
        my $t_end = 500;       
        my $stead_state = 1;
        my $opt= "prefix=>\"$prefix\",suffix=>\"$srun\",t_end=>$t_end,n_steps=>$entry->{'num_steps'}";
        if ($steady_state)
        {
          $opt .= ",steady_state=>1";
        }
        printf $fh_copy "simulate_ode({$opt});\n";
        $current_val += $delta;
      }
    } # done with entries for this model

    close $fh_copy or die "Couldn't save file '$model_path_copy'! $?";
    
  } # done with this model, next model...
}

1;
