#
# ScanBatch: Do batch simulations with BioNetGen for data collection
# by Daniel Packer
#

package ScanBatch;

use strict;
use warnings;

use File::Copy;

##############################################################################
# PROGRAM CONSTANTS:
#
use constant SB_CONSTANTS         => ('e'  => exp(1),
                                      'pi' => 3.14159265);
use constant VALID_PARAMS         => qw/config_file/;
use constant DEFAULT_NUM_RUNS     => 100;
use constant MODEL_DIR            => $ENV{'SB_MODEL_DIR'} || '.';
use constant SB_DATA_DIR          => $ENV{'SB_DATA_DIR'} || './sb_data';
use constant SB_PREFIX            => 'SB_';
use constant BNG_PATH             => $ENV{'BNGPATH'} || '.';
use constant SB_LOG_FILE          => 'scanbatch.log';
use constant DEFAULT_DO_EQ        => 1;
use constant DEFAULT_T_END        => 500;
use constant DEFAULT_N_STEPS      => 250;
use constant DEFAULT_DO_SPARSE    => 1;
use constant DEFAULT_MDL_SETTINGS => { 'sim_type'     => 'ssa',
                                       'do_eq'        => 1,
                                       'dist'         => 'even',
                                       't_end'        => 500,
                                       'n_steps'      => 250,
                                       'steady'       => 0,
                                       'do_sparse'    => 1,
                                       'eq_t_end'     => 10000,
                                       'eq_n_steps'   => 100000,
                                       'eq_do_sparse' => 10000,
                                       'eq_steady'    => 1,
                                     };


##############################################################################
# SCAN BATCH OBJECT:

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

  my %config_entries = (); # hold species entries indexed by model

  my $current_model = '';

  if (my $filename = $self->{'config_file'})
  {
    if (! -e $filename)
    {
      die "file '$filename' not found!";
    } else {
      open (my $fh, "<$filename") or die "Couldn't open file '$filename'! $!";

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
        die "no model context" unless defined($current_model);

        # Get default settings for this model
        $self->{'model_settings'}->{$current_model} = DEFAULT_MDL_SETTINGS
          unless defined($self->{'model_settings'}->{$current_model});

        # Get specific settings for this model, if any
        if (grep(/\w+\=\w+/, $line))
        {
          my ($key, $val) = split('\s*=\s*', $line);
          $self->{'model_settings'}->{$current_model}->{$key} = $self->process_param($val);
          next;
        }

        # Validate configuration line
        die "Invalid spec '$line'!" unless ($line =~ /^.*\s*\:\s*.+,.+,.+,.+$/);

        #print "line: $line\n";
        # Read the individual params on this line
        my ($param, $fields) = split(/\:\s*/, $line);
        my @fields = split(/\s*,\s*/, $fields);
        my ($start_val, $end_val, $num_steps) = map { $self->process_param($_) } @fields;
        my $num_runs = (scalar(@fields) == 4) ? pop (@fields) : DEFAULT_NUM_RUNS;

        my %config_entry = (
          'model'     => $current_model,
          'param'     => $param,
          'start_val' => $start_val,
          'end_val'   => $end_val,
          'num_steps' => $num_steps,
          'num_runs'  => $num_runs,
        );

        # Organize entries by model name
        if (! exists($self->{'config_entries'}->{$current_model}) )
        {
          $self->{'config_entries'}->{$current_model} = [];
        }
        push @{ $self->{'config_entries'}->{$current_model} }, \%config_entry;
        #print "[$param] [$start_val] [$end_val] [$num_steps]\n";

      } # end loop through lines     

      close $fh or die "Error: $!";

    } # end if file exists

  } # end if config

} # end sub


# Print the internal state of the object (data from config)
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

    # dump the model-specific settings
    print 'SETTINGS: ' . join(", ", 
      map { $_ . ': ' . $self->{'model_settings'}->{$model}->{$_} } (
        keys %{ $self->{'model_settings'}->{$model} }
      )
    ) . "\n";
    
    my @entries = @{ $self->{'config_entries'}->{$model} };
    for my $entry (@entries)
    {
      print "SPECIES ENTRY: ";
      print join (", ", (map { $_ . ': ' . $entry->{$_} } (keys %$entry)));
      print "\n";
    }
  }

  print "\n----------------------------------------------------------------------\n";
}


# Take all of the config entries and do the appropriate scans!
sub batch_scan {

  my $self = shift or die "Call via object!";

  my %config_entries = %{ $self->{'config_entries'} }; # get config entries

  # Create data dir
  if (! -e SB_DATA_DIR)
  {
    mkdir(SB_DATA_DIR) or die "Couldn't create data dir'! $!";
  }

  # Work on one model at a time
  for my $model (keys %config_entries)
  {
    # Does the model exist?
    die "No model defined" unless (exists $config_entries{$model});
    my $model_path = MODEL_DIR . '/' . $model;
    #print "MODEL PATH: $model_path\n";
    die "Model file '$model_path' not found!" unless (-e $model_path);

    # Create a subdirectory for this model
    my ($model_basename, $ext) = split('\.', $model);
    my $new_model_dir = SB_DATA_DIR . '/' . $model_basename; 
    mkdir($new_model_dir) or die "Couldn't mkdir '$new_model_dir'! $!";

    # Make a local copy of this config file & read the bngl script into memory
    open(my $fh, "<$model_path") or die "Couldn't open file '$model_path'! $!";
    my $script = "";
    while(<$fh>)
    {
      last if (/\s*end\s*model\s*/); # skip actions after model definition
      $script .= $_;
    }
    close $fh or die "Couldn't close file '$model_path'! $!";

    if (! -e SB_DATA_DIR) # Create temp dir
    {
      mkdir(SB_DATA_DIR) or die "Couldn't create temp dir '" . SB_DATA_DIR . " $!";
    }

    # Make local copy of model file to modify
    my $model_path_copy = SB_DATA_DIR . '/' . $model_basename . '/' . SB_PREFIX . $model;
    open(my $fh_copy, ">$model_path_copy") or die "Couldn't create file '$model_path_copy'! $!";
    print $fh_copy $script;

    # Process the config entries for this model
    my @extracted_entries = @{ $config_entries{$model} };

    # Pull out the entry to start scanning it
    #my @entry_field_names = qw/model param start_val end_val num_steps num_runs/;
    for my $entry (@extracted_entries)
    {

      # Make a directory for this param
      my $new_param_dir = SB_DATA_DIR . '/' . $model_basename . '/' . $entry->{'param'};
      if (! -e $new_param_dir)
      {
        mkdir($new_param_dir) or die "Couldn't create dir '$new_param_dir'! $!";
      }

      my %msettings = %{ $self->{'model_settings'}->{$model} };
      #use Data::Dumper; print "$model MSETTINGS!!!!! " . Dumper \%msettings;

      # BNGL code for equilibrium
      my $eq_prefix = $new_model_dir;
      my $eq_suffix = '';
      my $eq_code = qq(
generate_network({overwrite => 1});
simulate_ode({prefix=>"$eq_prefix", suffix=>"$eq_suffix",t_end=>$msettings{'eq_t_end'},n_steps=>$msettings{'eq_n_steps'},atol=>1e-10,rtol=>1e-8,steady_state=>$msettings{'eq_steady'},sparse=>$msettings{'eq_do_sparse'}});
);
      print $fh_copy "\n# Added by BatchScan - Equilibriation:" . $eq_code
        if ($msettings{'do_eq'});
      print $fh_copy "\n# Added by BatchScan - Save Concentrations:\n" . "saveConcentrations();\n";
      print $fh_copy "\n# Added by BatchScan - Setting paramters for '$entry->{'param'}':\n";

      # Begin the BNGL runs
      my $current_val = $entry->{'start_val'};
      my $run_count = 0;

print "ENTRY NS: " . $entry->{'num_steps'} . "\n";
      my $num_steps = $entry->{'num_steps'};

      for my $step_num (1..$num_steps)
      {
      print "$step_num: $num_steps\n";
        my $delta = 0; # Allow use of a single value for start/end

        if ($entry->{'end_val'} != $entry->{'start_val'})
        {
          # If we're doing exponential interpret config values:
          # start = coefficient
          # end   = base of exponent
          # steps = max exponent multiplier
          # runs = runs (no change)
          if (my $dist = $msettings{'dist'}) # exponential distribution
          {
            if ($dist eq 'exp')
            {
              $current_val = $entry->{'start_val'} * ($entry->{'end_val'} ** $run_count);
              $delta=0;
            }
            elsif ($dist eq 'even')
            { # default
              $current_val += $delta;
              $delta = ($entry->{'end_val'} - $entry->{'start_val'}) / ($entry->{'num_steps'} - 1);
            }
            else
            {
              die "Invalid distribtution type. Valid types: 'exp', 'even'";
            }
          }
          else 
          {
            die "No distribution type specified.";
          }
        }
        #print "CURRENT VAL: $current_val\n";

        # Make dir for this concentraiton and do this step num_runs times
        my $new_step_dir = $new_param_dir . '/' . $current_val;
        mkdir ($new_step_dir) or die "Couldn't create step dir '$new_step_dir'! $!";

        for my $run_num (1..$entry->{'num_runs'})
        {
          my $srun= sprintf "%05d", $run_num;
          print $fh_copy "resetConcentrations();\n\n" if ($step_num > 1);
          print $fh_copy "setConcentration(\"$entry->{'param'}\", $current_val);\n";
          my $prefix = $new_step_dir . '/' . $srun;
          my $stead_state = 1;
          my $opt = "prefix=>\"$prefix\",suffix=>\"\",t_end=>$msettings{'t_end'},n_steps=>$msettings{'n_steps'},output_step_interval=>1,atol=>1e-10,rtol=>1e-8,sparse=>$msettings{'do_sparse'},steady_state=>$msettings{'steady'}";
          print $fh_copy "simulate_$msettings{'sim_type'}({$opt});\n";
        } # done with runs

        $current_val += $delta;
        $run_count++;

     } # done with all steps

    } # done with entries for this model

    close $fh_copy or die "Couldn't save file '$model_path_copy'! $!";

    # Run BioNetGen on file
    print "\nRunning BioNetGen on '$model_path_copy'\n";
   
    # Search for the BNG2.pl file 
    #  (BNG 2.1.7 and 2.1.8 keep the .pl in diff places)
    my $exec = BNG_PATH . '/Perl2/BNG2.pl';
    $exec = BNG_PATH . '/BNG2.pl' if (! -e $exec);

    my $logfile = SB_DATA_DIR . '/' . SB_LOG_FILE; # save output of BNG2.pl
    system("$exec $model_path_copy > $logfile"); # Run BNG2.pl

  } # done with this model, next model...
  
  print "\nScanBatch is DONE!\n";
}

# Process config parameters
sub process_param {
  my $self = shift or die "Call via object!";
  my $param = shift;
  die "No param defined" unless defined($param);

  my $processed = $param; # default

  # we can handle scientific notation natively in perl but it's
  #  hard to tell what we're working with (even with POSIX module)
  #  so we implement our own sci notation code
  if (is_sci($param)) # is it scientific notation?
  {
    $processed = sci2dec($param);
  }
  elsif (is_const($param)) # is it a constant
  {
    $processed = unconst($param);
  }
  elsif (is_num($param)) # is it a number
  {
  }
  elsif (grep $param, qw/exp even/) # other
  {
  }
  else # we didn't recognize the param format!
  {
    die "Invalid paramter: '$param'!";
  }
  return $processed;
}


##############################################################################
# UTILITY FUNCTIONS:
 
# Return log(n) to a specific base, or natural log if no base provided.
sub log_base {
  my $n = shift;
  die "No number provided" unless defined($n);
  my $base = shift;
  if (defined($base))
  {
    return log($n)/log($base);
  } else {
    return log($n);
  }
} 


# Replace a constant symbol for a numerical value (e, pi, etc.)
sub unconst {
  my $n = shift;
  die "No number provided" unless defined($n);

  # Is this a constant?
  my %cons = SB_CONSTANTS;
  if (grep /$n/i, (keys %cons))
  {
    return $cons{lc($n)};
  } else {
    die "Invalid constant: '$n'!";
  }
}

# Is this a defined constant?
sub is_const {
  my $n = shift;
  die "No number provided" unless defined($n);
  my %cons = SB_CONSTANTS;
  return grep /$n/i, (keys %cons);
}


# Convert number in scientific notation to decimal
sub sci2dec {
  my $n = shift;
  die "No number provided" unless defined($n);
  
  my ($base, $exp) = is_sci($n);
  print "BASE: $base, EXP $exp\n";
  die "Invalid scientific notation formation for '$n'!"
    unless (defined($base) and defined($exp));

  return ($base * (10 ** $exp));
}

# Is this a scientific notation number?
sub is_sci {
  my $n = shift;
  print "N: $n\n";
  die "No number provided" unless defined($n);
  if ($n =~ /^(\-?\d+\.?\d*)[eE]+(\-?\d+\.?\d*)$/)
  {
    return $1, $2;
  }
}

# Is this a decimal number?
sub is_num {
  my $n = shift;
  die "No number provided" unless defined($n);
  return ($n =~ /^\d+\.?\d*$/);
}
 

1;
