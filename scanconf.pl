#!/usr/bin/perl -w

use strict;
use warnings;

my $fh;

my $filename = (scalar(@ARGV)==0) ? "scan.conf" : $ARGV[0];

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
    print "line: $line\n";

    my ($param, $start_val, $end_val, $num_steps) =
      split(/\s*,\s*/, $line);

    print "[$param] [$start_val] [$end_val] [$num_steps]\n";
  }      

  close $fh or die "$!";
}

