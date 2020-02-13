#!/usr/bin/perl -w

# This script identifies combinations
# of source and destination used by rclone,
# to create corresponding zabbix items.
# The script tries to remember used values
# for 10 days.

# Author: Sebastian Plocek
# https://github.com/sebastian13/zabbix-templates

use strict;
use warnings;
use 5.010;

if ($#ARGV != 1 ) {
	print "Error: Arguments Missing:\n";
	print "Usage: ./rclone-discovery.pl [source:sourcepath] [dest:destpath]\n";
	exit 1;
}

# Used Source/Dest should be remembered for 10 days
my $hist_file = '/tmp/rclone.history';

# Time (in seconds) to remember source/dest
my $age = 864000;
my $t_age = (time() - $age);

# Add current run to history file
open (my $fh, '+>>', $hist_file) or die;
print $fh time() . " $ARGV[0] $ARGV[1]\n";
close $fh;

# Read file
open my $read, '<', $hist_file or die;
my @lines = <$read>;
close $read;

# Rewrite the file, remove all lines that are older than $age.
open my $write, '>', $hist_file or die;
for (@lines) {
	my @tab = split(/\s+/, $_);
	print $write $_ unless( $tab[0] < $t_age );
}
close $write;

# Read file again
open my $read_new, '<', $hist_file;
chomp(my @lines_new = <$read_new>);
close $read_new;

# Read lines w/o timestamp to array
my @lines_pruned;
for (@lines_new) {
	my @tab = split(/\s+/, $_);
	push @lines_pruned, "$tab[1] $tab[2]\n";
}

# Remove Duplicates
sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}
my @lines_distinct = uniq(@lines_pruned);

# Print JSON
print "{\"data\":[";

my $first = 1;
for (@lines_distinct) {
	print "," if !$first;
    $first = 0;
    my @tab = split(/\s+/, $_);

	print "{";
	print "\"{#SOURCE}\":\"$tab[0]\",";
	print "\"{#DEST}\":\"$tab[1]\"";
	print "}";
}

print "]}";
