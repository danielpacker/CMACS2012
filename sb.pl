#!/usr/bin/perl -w

use strict;
use warnings;

use lib './lib';

use ScanBatch;

use constant CONF_FILE => (scalar(@ARGV)==0) ? 'scan.conf' : $ARGV[0];

my $sb = ScanBatch->new(
  'config_file' => CONF_FILE,
);

# Show state of object (data from config file)
$sb->dump();

# Run a batch scan  
$sb->batch_scan();

