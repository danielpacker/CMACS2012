#!/usr/bin/perl -w

use strict;
use warnings;

use lib './lib';

use ScanBatch;

use constant CONF_DIR     => './conf/';
use constant CONF_FILE    => 'sb.conf';
use constant CONF_DEFAULT => (scalar(@ARGV)==0) ? CONF_DIR . CONF_FILE : $ARGV[0];

my $sb = ScanBatch->new(
  'config_file' => CONF_DEFAULT
);

# Show state of object (data from config file)
$sb->dump();

# Run a batch scan  
$sb->batch_scan();

