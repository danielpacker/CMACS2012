#!/usr/bin/perl
# Simple parameter scanning script.  Creates and runs a single BNGL file that
# scans a single parameter using the setParameter command".  User provides
# a BNGL file containing the model - actions in this file are ignored.
#
# Written by Jim Faeder, Los Alamos National Laboratory, 3/6/2007 

my $BNGPATH=".";

my $delta= ($var_max-$var_min)/($n_pts-1);

# Read file 
open(IN,$file) || die "Couldn't open file $file: $?\n";
my $script="";
while(<IN>){
  $script.=$_;
  # Skip actions
  last if (/^\s*end\s*model\s*$/);
}

if (-d $prefix){
  system("rm -r $prefix");
#  die "Directory $prefix exists.  Remove before running this script.";
}

mkdir $prefix;
chdir $prefix;

# Create input file scanning variable
$fname= sprintf "${prefix}.bngl", $run;
open(BNGL,">$fname") || die "Couldn't write to $fname";
print BNGL $script;


print BNGL "generate_network({overwrite=>1});\n";
my $val= $var_min;
for my $run (1..$n_pts){
  my $srun= sprintf "%05d", $run;
  if ($run>1){
    print BNGL "resetConcentrations()\n";
  }
  my $x= $val;
  if ($log){ $x= exp($val);}
  printf BNGL "setParameter($var,$x);\n";
  
  my $opt= "prefix=>\"$prefix\",suffix=>\"$srun\",t_end=>$t_end,n_steps=>$n_steps";
  if ($steady_state){
    $opt.=",steady_state=>1";
  }
  printf BNGL "simulate_ode({$opt});\n";
  $val+=$delta;
}  
close(BNGL);

# Run BioNetGen on file
print "Running BioNetGen on $fname\n";
my $exec= '"${BNGPATH}/Perl2/BNG2.pl"';
system("$exec $fname > $prefix.log");

